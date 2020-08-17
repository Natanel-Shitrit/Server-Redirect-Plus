#include <sourcemod>
#include <steamworks>
#include <redirect_core>
#include <multicolors>

#pragma newdecls required
#pragma semicolon 1

// PREFIXs for the menus and chat messages
#define PREFIX " \x04[Server-Redirect+]\x01"
#define PREFIX_NO_COLOR "[Server-Redirect+]"

// Config file path
#define SETTINGS_PATH "configs/ServerRedirect/Config.cfg"

// Lenght as used in the Database.
#define MAX_SERVER_NAME_LENGHT 245
#define MAX_CATEGORY_NAME_LENGHT 64

// Regex string
#define REGEX_COUNT_STRINGS "{(shortname|longname|category|map)}"

//============[ DB ]============//
Database DB = null;								// Database handle
char Query[512];								// Query string for quering 

//=======[ Update Timer ]=======//
Handle g_hServerUpdateTimer = null;				// Update this server
int g_iTimerCounter;							// Timer For Advertisements

//==========[ Settings ]=========//
ConVar 	g_cvUpdateOtherServersInterval; 		// Timer Interval for other servers update
ConVar 	g_cvUpdateServerInterval; 				// Time between each update
ConVar 	g_cvPrintDebug; 						// Debug Mode Status

ConVar 	g_cvNetPublicAdr;						// Public IP Adress, could be set manually from srdc launch options
ConVar 	g_cvReservedSlots;						// Number of reserved slots.
ConVar 	g_cvHiddenSlots;						// If the reserved slots are hidden or not.

bool 	g_bShowServerOnServerList; 				// Show this server in the Server-List?
bool 	g_bAdvertisementsAreEnabled; 			// Should we advertise servers?
bool 	g_bAdvertiseOfflineServers; 			// Should we advertise offline servers?

char 	g_sServerListCommands[256];				// Commands for the Server-List.
char 	g_sMenuFormat[256]; 					// Menu Server Format
char 	g_sPrefixRemover[128]; 					// String to remove from the server name (useful for removing prefixs)

int 	g_iServerTimeOut;						// The amount of time before this server will be deleted from the database after the last update

//======[ Settings Related ]====//
Regex rgCountStrings;

//=======[ ADV TYPE ENUM ]======//
enum
{
	ADVERTISEMENT_PLAYERS_RANGE = -2,  	// USING DEFFRENCE CHECK
	ADVERTISEMENT_MAP 		 		, 	// USING DEFFRENCE CHECK
	ADVERTISEMENT_LOOP		 			// USING TIMER
}

//======[ ADV ERROR ENUM ]======//
enum
{
	// LOOP START
	ERROR_INVALID_SERVER_ID = 1	,
	ERROR_EMPTY_MESSAGE_CONTENT	,
	ERROR_INVALID_PLAYER_RANGE	,
	ERROR_INVALID_PLAYER_RANGE_START,
	ERROR_INVALID_PLAYER_RANGE_END	,
	// LOOP END
	ERROR_INVALID_LOOP_TIME,
	ERROR_INVALID_COOLDOWN_TIME
}

//======[ UPDATE ADV ENUM ]=====//
enum
{
	UPDATE_NOTHING = -1	,
	UPDATE_LOOP_TIME 	,
	UPDATE_COOLDOWN_TIME,
	UPDATE_PLAYER_RANGE ,
	UPDATE_ADV_MESSAGE
}
int g_iUpdateAdvProprietary[MAXPLAYERS + 1] =  { UPDATE_NOTHING, ... };

//====[ SERVER SEARCH ENUM ]====//
enum
{
	SERVER_SEARCH_BY_STEAM_ID = 0,
	SERVER_SEARCH_BY_BACKUP_ID
}

//======[ DB UPDATE ENUM ]======//
enum
{
	UPDATE_SERVER_STEAM_ID,
	UPDATE_SERVER_PLAYERS,
	UPDATE_SERVER_STATUS, 
	UPDATE_SERVER_START
}

//========[ TABLE STRUCT ]======//
enum
{
	SQL_FIELD_SERVER_BACKUP_ID = 1,
	SQL_FIELD_SERVER_STEAM_ID,
	SQL_FIELD_SERVER_NAME,
	SQL_FIELD_SERVER_CATEGORY,
	SQL_FIELD_SERVER_IP,
	SQL_FIELD_SERVER_PORT,
	SQL_FIELD_SERVER_STATUS,
	SQL_FIELD_SERVER_VISIBLE,
	SQL_FIELD_SERVER_MAP,
	SQL_FIELD_SERVER_PLAYERS,
	SQL_FIELD_SERVER_RESERVED_SLOTS,
	SQL_FIELD_SERVER_HIDDEN_SLOTS,
	SQL_FIELD_SERVER_MAX_PLAYERS,
	SQL_FIELD_SERVER_INCLUD_BOTS,
	SQL_FIELD_SERVER_LAST_UPDATE,
	SQL_FIELD_SERVER_TIMEOUT,
	SQL_FIELD_SERVER_LAST_UPDATE_UNIX
}

//=======[ SERVER STRUCT ]======//
enum struct Server
{
	char sServerCategory[MAX_CATEGORY_NAME_LENGHT];
	char sServerName[MAX_SERVER_NAME_LENGHT];
	char sServerMap[PLATFORM_MAX_PATH];
	
	int iReservedSlots;
	int iNumOfPlayers;
	int iServerIP32;
	int iServerPort;
	int iMaxPlayers;
	int iServerSteamAID;
	int iServerBackupID;
	
	bool bShowInServerList;
	bool bServerStatus;
	bool bHiddenSlots;
	bool bIncludeBots;
	
	void Reset()
	{
		this.sServerCategory = "";
		this.sServerName 	 = "";
		this.sServerMap 	 = "";
		
		this.iReservedSlots  = 0;
		this.iNumOfPlayers	 = 0;
		this.iServerIP32	 = 0;
		this.iServerPort	 = 0;
		this.iMaxPlayers	 = 0;
		this.iServerSteamAID = 0;
		this.iServerBackupID = 0;
		
		this.bShowInServerList = false;
		this.bServerStatus 	   = false;
		this.bHiddenSlots 	   = false;
		this.bIncludeBots 	   = false;
	}
	
	bool IsTimedOut(Handle hQuery)
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.IsTimedOut() | iServerSteamAID = %d", this.iServerSteamAID);
		
		int iServerTimeOut = SQL_FetchInt(hQuery, SQL_FIELD_SERVER_TIMEOUT) * 60;
		if(iServerTimeOut > 0)
		{
			int iServerLastUpdate 		 = SQL_FetchInt(hQuery, SQL_FIELD_SERVER_LAST_UPDATE_UNIX);
			int iServerTimeWithoutUpdate = GetTime() - iServerLastUpdate;
			
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Deleting Server (Server Steam ID - %d | Last update - %d | timeout time in sec - %d | time without update %d)",
					this.iServerSteamAID,
					iServerLastUpdate,
					iServerTimeOut,
					iServerTimeWithoutUpdate
				);
				
			return (iServerTimeWithoutUpdate >= iServerTimeOut);
		}
		
		return false;
	}
	
	void DeleteFromDB()
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.DeleteFromDB() | iServerSteamAID = %d", this.iServerSteamAID);
		
		Format(Query, sizeof(Query), "DELETE FROM `server_redirect_servers` WHERE `server_steam_id` = %d", this.iServerSteamAID);
					
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Delete Server Query: %s", Query);
	
		DB.Query(T_FakeFastQuery, Query, _, DBPrio_Low);
	}
	
	// Registering a new server in the Database server.
	void Register()
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.Register() | iServerSteamAID = %d", this.iServerSteamAID);
		
		DB.Format(Query, sizeof(Query), "INSERT INTO `server_redirect_servers` (`server_backup_id`, `server_steam_id`, `server_name`, `server_category`, `server_ip`, `server_port`, `server_status`, `server_map`, `number_of_players`, `max_players`, `reserved_slots`, `hidden_slots`, `server_visible`, `timeout_time`) VALUES (%d, %d, '%s', '%s', %d, %d, %d, '%s', %d, %d, %d, %d, %b, %d)", 
			this.iServerBackupID,
			this.iServerSteamAID,
			this.sServerName, 
			this.sServerCategory, 
			this.iServerIP32, 
			this.iServerPort, 
			this.bServerStatus, 
			this.sServerMap, 
			this.iNumOfPlayers, 
			this.iMaxPlayers,
			this.iReservedSlots,
			this.bHiddenSlots,
			this.bShowInServerList,
			g_iServerTimeOut
		);
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Register Query: %s", Query);
		
		DB.Query(T_FakeFastQuery, Query, _, DBPrio_High);
	}
	
	// Updating the server information based of the sent parameter.
	void UpdateInDB(int iWhatToUpdate, DBPriority dbPriority = DBPrio_Normal)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.UpdateInDB() | iWhatToUpdate = %d", iWhatToUpdate);
		
		// TODO: Easy formatting, testing needed:
		// Each UPDATE_TYPE will have a string and will be formatted in this template:
		//Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET {CHANGE} WHERE `server_steam_id` = %d")
		
		switch (iWhatToUpdate)
		{
			case UPDATE_SERVER_STEAM_ID:
			{
				Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `server_steam_id` = %d WHERE `server_backup_id` = %d",
					this.iServerSteamAID,
					this.iServerBackupID
				);
			}
			case UPDATE_SERVER_PLAYERS:
			{
				// Get Client-Count
				this.iNumOfPlayers = GetClientCountEx(this.bIncludeBots);
				
				Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `number_of_players` = %d WHERE `server_steam_id` = %d",
					this.iNumOfPlayers,
					this.iServerSteamAID
				);
			}
			case UPDATE_SERVER_STATUS:
			{
				Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `server_status` = %d WHERE `server_steam_id` = %d",
					this.bServerStatus,
					this.iServerSteamAID
				);
			}
			case UPDATE_SERVER_START:
			{
				DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `server_name` = '%s', `server_ip` = %d, `server_port` = %d, `server_status` = %d, `server_visible` = %d, `max_players` = %d, `reserved_slots` = %d, `hidden_slots` = %b, `bots_included` = %b, `server_map` = '%s', `timeout_time` = %d WHERE `server_steam_id` = %d",
					this.sServerName,
					this.iServerIP32,
					this.iServerPort,
					this.bServerStatus,
					this.bShowInServerList,
					this.iMaxPlayers,
					this.iReservedSlots,
					this.bHiddenSlots,
					this.bIncludeBots,
					this.sServerMap,
					g_iServerTimeOut,
					this.iServerSteamAID
				);
			}
		}
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Update Query: %s", Query);
		
		DB.Query(T_FakeFastQuery, Query, _, dbPriority);
	}
	
	void UpdateServerAdvertisements(int iOutdatedServerSteamAID)
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.DeleteFromDB() | iServerSteamAID = %d (Outdated: %d)", this.iServerSteamAID, iOutdatedServerSteamAID);
		
		Format(Query, sizeof(Query), "UPDATE `server_redirect_advertisements` SET `server_id_to_adv` = %d WHERE `server_id_to_adv` = %d", this.iServerSteamAID, iOutdatedServerSteamAID);
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("`server_id_to_adv` Query: %s", Query);
		
		DB.Query(T_FakeFastQuery, Query);
		
		Format(Query, sizeof(Query), "UPDATE `server_redirect_advertisements` SET `server_id` = %d WHERE `server_id` = %d", this.iServerSteamAID, iOutdatedServerSteamAID);
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("`server_id_to_adv` Query: %s", Query);
		
		DB.Query(T_FakeFastQuery, Query);
	}
}
ArrayList g_hOtherServers;
Server g_srThisServer;

//=====[ ADVERTISEMENT ENUM ]===//
enum struct Advertisement
{
	int iPlayersRange[2]; 		// 0 - MIN | 1 - MAX
	
	int iServerSteamAIDToAdvertise;	// Advertised Server
	int iAdvertisedTime;		// Used for calculating if the advertisement should post
	int iCoolDownTime;			// How long should this advertisement should be on cooldown (for 'deffrence check' advertisements)
	int iRepeatTime;			// How long to wait between each advertise
	int iAdvID;					// Advertisement ID
	
	char sMessageContent[512];	// Message to print
	
	bool bActive;				// If the advertisement is currently active
	
	void Reset()
	{
		this.iPlayersRange = {0, 0};
		
		this.iServerSteamAIDToAdvertise = 0;
		this.iAdvertisedTime = 0;
		this.iCoolDownTime 	 = 0;
		this.iRepeatTime 	 = 0;
		this.iAdvID 		 = 0;
		
		this.sMessageContent = "";
		
		this.bActive = false;
	}
	
	void DeleteFromDB()
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Advertisement.DeleteFromDB() | iAdvID = %d", this.iAdvID);	
	
		Format(Query, sizeof(Query), "DELETE FROM `server_redirect_advertisements` WHERE `id` = %d", this.iAdvID);	
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("Query: %s", Query);
		
		DB.Query(T_UpdateAdvertisementQuery, Query, false);
	}
	
	void UpdateOnDB()
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Advertisement.UpdateOnDB() | iAdvID = %d", this.iAdvID);
		
		char sPlayersRange[6];
		Format(sPlayersRange, sizeof(sPlayersRange), "%d|%d", this.iPlayersRange[0], this.iPlayersRange[1]);
		
		DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_advertisements` SET `server_id_to_adv` = %d, `adv_repeat_time` = %d, `adv_cooldown_time` = %d, `adv_players_range` = '%s', `adv_message` = '%s' WHERE `id` = %d",
			this.iServerSteamAIDToAdvertise,
			this.iRepeatTime,
			this.iCoolDownTime,
			sPlayersRange,
			this.sMessageContent,
			this.iAdvID
		);
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("Query: %s", Query);
		
		DB.Query(T_UpdateAdvertisementQuery, Query, false);
	}
	
	void AddToDB()
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Advertisement.AddToDB() | iAdvID = %d", this.iAdvID);
		
		char sPlayersRange[6];
		Format(sPlayersRange, sizeof(sPlayersRange), "%d|%d", this.iPlayersRange[0], this.iPlayersRange[1]);
		
		DB.Format(Query, sizeof(Query), "INSERT INTO `server_redirect_advertisements`(`server_id`, `server_id_to_adv`, `adv_repeat_time`, `adv_cooldown_time`, `adv_message`, `adv_players_range`) VALUES (%d, %d, %d, %d, '%s', '%s')",
			g_srThisServer.iServerSteamAID,
			this.iServerSteamAIDToAdvertise,
			this.iRepeatTime,
			this.iCoolDownTime,
			this.sMessageContent,
			sPlayersRange
		);
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("Query: %s", Query);
		
		DB.Query(T_UpdateAdvertisementQuery, Query);
	}
}
ArrayList g_hAdvertisements; // All of the server advertisements
Advertisement g_advToEdit;	 // For editing / adding advertisements

// Late Load
bool g_bLateLoad;

//=========[ INCLUDES ]=========//
#include "ServerRedirectMenus.sp"
#include "ServerRedirectAdvertisements.sp"

//=======[ PLUGIN INFO ]========//
public Plugin myinfo = 
{
	name = "[Server-Redirect+] Core", 
	author = "Natanel 'LuqS'", 
	description = "Core of 'Server-Redirect+', gathering information about the server and sending it to the SQL Database.", 
	version = "2.3.0", 
	url = "https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
};

//=========[ EVENTS ]===========//
public void OnPluginStart()
{
	// We don't want to run on other games than CS:GO, only tested in CS:GO
	// NOTE: You can remove this but i can't guarantee that it will work in other games.
	if (GetEngineVersion() != Engine_CSGO)
		SetFailState("%s This plugin is for CSGO only.", PREFIX_NO_COLOR);
		
	LogMessage("Plugin Started.");
	
	rgCountStrings = CompileRegex(REGEX_COUNT_STRINGS);
	//==============================[ HOOKS ]===========================//
	HookEvent("server_spawn"	, Event_ServerSpawn		, EventHookMode_Post);
	
	//==========================[ Console-Vars ]========================//
	g_cvUpdateOtherServersInterval 	= CreateConVar("server_redirect_other_servers_update_interval"	, "20.0", "The number of seconds between other servers update."											, _, true, 5.0, true, 600.0	);
	g_cvUpdateServerInterval 		= CreateConVar("server_redirect_server_update_interval"			, "20.0", "The number of seconds the plugin will wait before updating player count in the SQL server." 	, _, true, 0.0, true, 600.0	);
	g_cvPrintDebug 					= CreateConVar("server_redirect_debug_mode"						, "0"	, "Whether or not to print debug messages in server console"									, _, true, 0.0, true, 1.0	);
	
	//=========================[ AutoExec Config ]======================//
	AutoExecConfig(true);
	
	//=======================[ Other Console-Vars ]=====================//
	g_cvNetPublicAdr  = FindConVar("net_public_adr"		);
	g_cvReservedSlots = FindConVar("sm_reserved_slots"	);
	g_cvHiddenSlots	  = FindConVar("sm_hide_slots"		);
	
	//========================[ Load Translations ]=====================//
	LoadTranslations("server_redirect.phrases");
	
	// If this is a late load, fire the start up proccess right away.
	if(g_bLateLoad)
		PluginStartUpProccess();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_bLateLoad = late;
}

// We are getting the Server info here because some things are invalid before,
// And we must load the database only after we know we have everyting to send.
public Action Event_ServerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Event_ServerSpawn");
		
	PluginStartUpProccess();
}

public void OnMapStart()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnMapStart");
	
	// Get Server info to send to the database
	GetServerInfo();
}

// OnClientPostAdminCheck Will start the Server-Update timer if it's not already running.
public void OnClientPostAdminCheck(int client)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnClientPostAdminCheck | int client =  %d", client);
	
	// Check if the client is a bot and if the server doesn't want to take bots into account (continue if the client is not fake)
	// Yes: Starting the update Player-Count timer.
	if (!IsFakeClient(client) || g_srThisServer.bIncludeBots)
	{
		StartUpdateTimer();
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Next update will be in %d seconds.", g_cvUpdateServerInterval.IntValue);
	}
}

// OnClientDisconnect Will start the Server-Update timer if it's not already running.
public void OnClientDisconnect(int client)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnClientDisconnect | int client =  %d", client);
	
	// Check if the client is a bot and if the server doesn't want to take bots into account (continue if the client is not fake)
	// Yes: Starting the update Player-Count timer.
	if (!IsFakeClient(client) || g_srThisServer.bIncludeBots)
	{
		// Get the server Player-Count.
		g_srThisServer.iNumOfPlayers = GetClientCountEx(g_srThisServer.bIncludeBots) - 1;
		
		if (g_cvPrintDebug.BoolValue)
				LogMessage("Number of remaining clients - %d", g_srThisServer.iNumOfPlayers);
		
		// Check If there are players in the server:
		// YES:	start the Player-Count timer.
		// NO:	Update the Player-Count right away. (all of the players left)
		if(!g_srThisServer.iNumOfPlayers)
		{
			StartUpdateTimer();
			
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Next update will be in %d seconds.", (g_srThisServer.iNumOfPlayers != 0) ? g_cvUpdateServerInterval.IntValue : 0);
		}
		else
		{
			g_srThisServer.UpdateInDB(UPDATE_SERVER_PLAYERS);
			
			// Stop the update timer if it's running
			if (!g_hServerUpdateTimer)
				delete g_hServerUpdateTimer;
		}
	}
}

// If the plugin is getting unloaded, probably the server is off so we want to update the server status in the database.
// Updating the Server-Status in the SQL server before plugin unload.
public void OnPluginEnd()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnPluginEnd");
	
	// Check if the server has a valid Backup-ID:
	// YES: Don't delete the server. Just make it offline.
	// NO:	Delete it from the database now. (we can't be sure we will find the server when it's back online)
	if(g_srThisServer.iServerBackupID > 0)
	{
		g_srThisServer.bServerStatus = false;
		g_srThisServer.UpdateInDB(UPDATE_SERVER_STATUS);
	}
	else
	{
		Format(Query, sizeof(Query), "DELETE FROM `server_redirect_servers` WHERE `server_steam_id` = %d", g_srThisServer.iServerSteamAID);
		DB.Query(T_FakeFastQuery, Query, _, DBPrio_High);
	}
}

//==================================[ TIMERS ]==============================//

// Main Timer for the Advertisements and updating the player count.
Action Timer_Loop(Handle hTimer)
{
	// If there are no players in the server, don't bother advertising or updating other servers. Because no one can use it / see it.
	if (!g_srThisServer.iNumOfPlayers)
		return Plugin_Continue;
	
	++g_iTimerCounter;
	
	// Every X seconds, update all other servers.
	if(g_iTimerCounter % g_cvUpdateOtherServersInterval.IntValue == 0)
		LoadServers();
	
	// If advertisements are enabled, try to find advertisements to post.
	if(g_bAdvertisementsAreEnabled)
	{
		Advertisement advCurrentAdvertisement;
		
		// Loop throw all the advertisements (all valid advertisements).
		for (int iCurrentAdvertisement = 0; iCurrentAdvertisement < g_hAdvertisements.Length; iCurrentAdvertisement++)
		{
			advCurrentAdvertisement = GetAdvertisementByIndex(iCurrentAdvertisement);
			
			// If this advertisement is invalid, everything after it would be the same because we are loading the all of the advertisements to the start of the array.
			if(!advCurrentAdvertisement.iAdvID)
				break;
			
			// If the advertisement isn't a LOOP type, continue to the next one
			if(advCurrentAdvertisement.iRepeatTime < ADVERTISEMENT_LOOP)
				continue;
			
			// If this is the time to post the advertisement, go for it.
			if(g_iTimerCounter % advCurrentAdvertisement.iRepeatTime == 0)
				PostAdvertisement(advCurrentAdvertisement.iServerSteamAIDToAdvertise, ADVERTISEMENT_LOOP, iCurrentAdvertisement);
		}
	}
	
	return Plugin_Continue;
}

// After the Update-Interval time has passed, updae the server.
Action Timer_UpdateServerInDatabase(Handle timer)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Timer_UpdateServerInDatabase");
	
	// Update on the database
	g_srThisServer.UpdateInDB(UPDATE_SERVER_PLAYERS);
	
	// Set the timer back to null.
	g_hServerUpdateTimer = null;
}

//==================================[ DB-STUFF ]==============================//
// Loading the Database config from sourcemod/configs/databases.cfg, checking if the table existes and if not creating a new one.
void LoadDB()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadDB");
	
	// Check if the Database handle is null (not connected to the database)
	// YES: Connect to the database.
	// NO:	Just Continue without connecting to the database again.
	if(DB == null)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Starting Full Database load");
		
		// Check if the comfig exists in the 'databases.cfg' config.
		// YES: Connect to the database.
		// NO:	Stop the plugin and throw an error.
		if (SQL_CheckConfig("ServerRedirect"))
			Database.Connect(T_OnDBConnected, "ServerRedirect");
		else
			SetFailState("%s Cannot find 'ServerRedirect` config in databases.cfg", PREFIX_NO_COLOR);
	}
	else
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Already got a Database connection, just updating the server.");
		
		// Find the server in the database.
		FindServer();
	}
}

// When we got a response from the db and we either connected or not.
void T_OnDBConnected(Database dbMain, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnDBConnected");
	
	// Check if the database handle we got is null (invalid connection)
	// YES:	Stop the plugin.
	// NO: Save the connection and create the servers database table.
	if (dbMain == null) // Oops, something went wrong :S
		SetFailState("%s Cannot Connect To MySQL Server! | Error: %s", PREFIX_NO_COLOR, sError);
	else
	{
		// Save the database globally to send queries :D
		DB = dbMain;
		
		// Create Tables
		DB.Query(T_OnDatabaseReady, "CREATE TABLE IF NOT EXISTS `server_redirect_servers` (`id` INT NOT NULL AUTO_INCREMENT, `server_backup_id` INT NOT NULL, `server_steam_id` INT NOT NULL, `server_name` VARCHAR(245) NOT NULL, `server_category` VARCHAR(64) NOT NULL, `server_ip` INT NOT NULL DEFAULT '-1', `server_port` INT NOT NULL DEFAULT '0', `server_status` INT NOT NULL DEFAULT '0', `server_visible` INT NOT NULL DEFAULT '1', `server_map` VARCHAR(64) NOT NULL, `number_of_players` INT NOT NULL DEFAULT '0', `reserved_slots` INT NOT NULL DEFAULT '0', `hidden_slots` INT(1) NOT NULL DEFAULT '0', `max_players` INT NOT NULL DEFAULT '0', `bots_included` INT NOT NULL DEFAULT '0', `unix_lastupdate` TIMESTAMP on update CURRENT_TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, `timeout_time` INT NOT NULL DEFAULT '0', PRIMARY KEY (`id`), UNIQUE(`server_steam_id`))", _, DBPrio_High);
	}
}

// Now the database is ready and we have a valid table to work with.
void T_OnDatabaseReady(Handle owner, Handle hQuery, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnDatabaseReady");
	
	if (hQuery != INVALID_HANDLE)
	{
		// Find the server in the database.
		FindServer();
	}
	else
		LogError("Error in T_OnDatabaseReady: %s", sError);
}

// Updating the server info in the Database server.
void FindServer(int iSearchBy = SERVER_SEARCH_BY_STEAM_ID)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- FindServer | iSearchBy - %d", iSearchBy);
	
	Format(Query, sizeof(Query), "SELECT `server_steam_id` FROM `server_redirect_servers` WHERE `%s` = %d",
		(!iSearchBy) ? "server_steam_id" : "server_backup_id",
		(!iSearchBy) ? g_srThisServer.iServerSteamAID : g_srThisServer.iServerBackupID);
		
	if (g_cvPrintDebug.BoolValue)
		LogMessage("FindServer Query: %s", Query);
	
	DB.Query(T_OnServerSearchResultsReceived, Query, iSearchBy, DBPrio_High);
}

void T_OnServerSearchResultsReceived(Handle owner, Handle hQuery, const char[] sError, any iSearchBy)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnServerSearchResultsReceived");
	
	if (hQuery != INVALID_HANDLE)
	{
		// If the row is fetched, that means we found the server. No rows = server doesn't exit in the DB.
		if(SQL_FetchRow(hQuery))
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Found Server %s-ID - %d", (iSearchBy == SERVER_SEARCH_BY_STEAM_ID) ? "Steam" : "Backup", (iSearchBy == SERVER_SEARCH_BY_STEAM_ID) ? g_srThisServer.iServerSteamAID : g_srThisServer.iServerBackupID);
			
			// If we found the server Backup-ID after not finding by Steam-ID, update the Steam-ID
			if(iSearchBy == SERVER_SEARCH_BY_BACKUP_ID)
			{
				// Update advertisements (Change old Server Steam-ID to the new one)
				int iOutdatedServerSteamID = SQL_FetchInt(hQuery, 0);
				g_srThisServer.UpdateServerAdvertisements(iOutdatedServerSteamID);
				
				// Update the new Steam-ID
				g_srThisServer.UpdateInDB(UPDATE_SERVER_STEAM_ID, DBPrio_High);
			}
			
			// Update the server.
			g_srThisServer.UpdateInDB(UPDATE_SERVER_START, DBPrio_Normal);
		}
		else 
		{
			// If the server wansn't found with the SteamAID and there is a valid Backup-ID, try recovering it.
			if(iSearchBy == SERVER_SEARCH_BY_STEAM_ID && g_srThisServer.iServerBackupID > 0)
			{
				if (g_cvPrintDebug.BoolValue)
					LogMessage("Couldn't find any servers with this Steam-ID (%d), Searching for the Server Backup-ID", g_srThisServer.iServerSteamAID);
				
				// Try to find the server with the Backup-ID
				FindServer(SERVER_SEARCH_BY_BACKUP_ID);
				
				// Don't Load all other servers yet.
				return;
			}
			else // Register the server with the Server-ID.
				g_srThisServer.Register();
		}
		
		// Load all other servers
		LoadServers(true);
	}
	else
		SetFailState("Something is wrong with the Database, Error in T_OnServerSearchReceived: %s", sError);
}

// We only need to send the query, nothing to receive.
void T_FakeFastQuery(Handle owner, Handle hQuery, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_FakeFastQuery");
	
	if (hQuery == INVALID_HANDLE)
		LogError("Error in T_FakeFastQuery: %s", sError);
}

//==================================[ HELPING ]==============================//
void PluginStartUpProccess()
{
	// Load Settings from the config
	LoadSettings();
	
	// Load the Server-List commands from the convar / config
	LoadServerListCommands();
	
	// Loading the Database
	LoadDB();
	
	// Starting the loop timer
	CreateTimer(1.0, Timer_Loop, _, TIMER_REPEAT);
}

// Load Server Settings
void LoadSettings()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadSettings");
	
	KeyValues kvSettings = CreateKeyValues("ServerRedirectSettings");
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), SETTINGS_PATH);
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if(!kvSettings.ImportFromFile(sPath) || !kvSettings.JumpToKey("Settings"))
		SetFailState("%s Couldn't load plugin config.", PREFIX_NO_COLOR);
	
	// Get the ServerID
	g_srThisServer.iServerBackupID = kvSettings.GetNum("ServerBackupID", 0);
	
	g_srThisServer.iServerSteamAID = GetServerSteamAccountId();
		
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Server Steam Accound-ID: %d", g_srThisServer.iServerSteamAID);
	
	// If we don't have the server steam account id and we didn't got a ServerID ask for a manual configuration.
	if(g_srThisServer.iServerSteamAID == 0)
		SetFailState("Couldn't get the Server Steam Account ID, please make sure the server is using a valid token!");
	
	// Get the rest of the settings if everything is ok
	g_srThisServer.bShowInServerList = view_as<bool>(kvSettings.GetNum("ShowSeverInServerList"	, 1));
	g_srThisServer.bIncludeBots 		= view_as<bool>(kvSettings.GetNum("ShowBots"				, 0));
	g_bAdvertisementsAreEnabled 		= view_as<bool>(kvSettings.GetNum("EnableAdvertisements"	, 1));
	g_bAdvertiseOfflineServers 			= view_as<bool>(kvSettings.GetNum("AdvertiseOfflineServers"	, 0));
	
	g_iServerTimeOut = kvSettings.GetNum("ServerTimeOut", 1440);
	
	kvSettings.GetString("MenuFormat"			, g_sMenuFormat						, sizeof(g_sMenuFormat)						);
	kvSettings.GetString("PrefixRemover"		, g_sPrefixRemover					, sizeof(g_sPrefixRemover)					);
	kvSettings.GetString("ServerListCommands"	, g_sServerListCommands				, sizeof(g_sServerListCommands)				);
	kvSettings.GetString("ServerName"			, g_srThisServer.sServerName		, sizeof(g_srThisServer.sServerName)		);
	kvSettings.GetString("ServerCategory"		, g_srThisServer.sServerCategory	, sizeof(g_srThisServer.sServerCategory)	);
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Settings Loaded:\nServerBackupID: %d\nMenuFormat: %s\nServerListCommands: %s\nServerName: %s\nServerCategory: %s\nShowBots: %d\nShowSeverInServerList: %d",
			g_srThisServer.iServerSteamAID,
			g_sMenuFormat,
			g_sServerListCommands,
			g_srThisServer.sServerName,
			g_srThisServer.sServerCategory,
			g_srThisServer.bIncludeBots,
			g_bShowServerOnServerList
		);
}

// Starting the server update timer if it's not already running.
void StartUpdateTimer()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- StartUpdateTimer | ServerUpdateTimer %s", g_hServerUpdateTimer ? "Already running" : "Started");
	
	if (!g_hServerUpdateTimer)
		g_hServerUpdateTimer = CreateTimer(g_cvUpdateServerInterval.FloatValue, Timer_UpdateServerInDatabase);
}

// Load the commands for the Server-List
void LoadServerListCommands()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadServerListCommands | Commands string - %s", g_sServerListCommands);
	
	// Get the commands separated from each other.
	char sSingleCommands[32][16];
	ExplodeString(g_sServerListCommands, ",", sSingleCommands, sizeof(sSingleCommands), sizeof(sSingleCommands[]));
	
	// Go over all the commands and register them
	for (int iCurrentCommand = 0; !StrEqual(sSingleCommands[iCurrentCommand], "", false); iCurrentCommand++)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("sSingleCommands[%d]: %s", iCurrentCommand, sSingleCommands[iCurrentCommand]);
			
		RegConsoleCmd(sSingleCommands[iCurrentCommand], Command_ServerList, "Opens the Server-List Menu.");
	}
}

// Get the name of the workshop map.
void GetCurrentWorkshopMap(char[] sMap, int iMapBufferSize)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- GetCurrentWorkshopMap | sMap - %s, iMapBufferSize - %d", sMap, iMapBufferSize);
	
	char sCurMap[128];
	char sMapSplit[2][64];
	
	GetCurrentMap(sCurMap, sizeof(sCurMap));
	ReplaceString(sCurMap, sizeof(sCurMap), "workshop/", "", false);
	ExplodeString(sCurMap, "/", sMapSplit, 2, 64);
	
	strcopy(sMap, iMapBufferSize, sMapSplit[1]);
}

// Getting the number of players that aren't bots.
int GetClientCountEx(bool bIncludeBots)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage("<-- GetClientCountEx | bIncludeBots - %d", bIncludeBots);
	
	int iClientCount = 0;
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		if (IsClientInGame(iCurrentClient) && (!IsFakeClient(iCurrentClient) || bIncludeBots))
			iClientCount++;
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("%d real clients are in the server. (with%s bots)", iClientCount, bIncludeBots ? "" : "out");
	
	return iClientCount;
}

// Copying a string to it's destination and adding a '...' if the string isn't fully shown.
int CopyStringWithDots(char[] sDest, int iDestLen, char[] sSource)
{
	strcopy(sDest, iDestLen, sSource);
	
	if(strlen(sSource) > iDestLen && iDestLen > 3)
		strcopy(sDest[iDestLen - 4], iDestLen, "...");
	
	return iDestLen - strlen(sSource);
}

// Getting the Server-IP32
int GetServerIP32()
{
	// Gets the server public IP
	int iIPFull[4];
	SteamWorks_GetPublicIP(iIPFull);
	
	if(!iIPFull[0])
	{
		char sIPv4[17];
		GetConVarString(g_cvNetPublicAdr, sIPv4, sizeof(sIPv4));
		
		char sIPFull[4][4];
		ExplodeString(sIPv4, ".", sIPFull, sizeof(sIPFull), sizeof(sIPFull[]));
		
		for (int iCurrentField = 0; iCurrentField < 4; iCurrentField++)
			iIPFull[iCurrentField] = StringToInt(sIPFull[iCurrentField]);
	}
	
	// Save the IP32
	int iFullIP32 = iIPFull[0] << 24 | iIPFull[1] << 16 | iIPFull[2] << 8 | iIPFull[3];
	
	// If the IP32 is 0 we need to get it in another way. If it's still 0 just return it :/
	return iFullIP32 == 0 ? FindConVar("hostip").IntValue : iFullIP32;
}

// Getting the server info and storing it.
void GetServerInfo()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- GetServerInfo");
	
	// If it's blank, grab the server hostname
	if (StrEqual(g_srThisServer.sServerName, "", false))
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Server name was empty. Getting the hostname.");
		
		GetConVarString(FindConVar("hostname"), g_srThisServer.sServerName, sizeof(g_srThisServer.sServerName));
	}
	
	// Get server map
	GetCurrentMap(g_srThisServer.sServerMap, sizeof(g_srThisServer.sServerMap));
	
	// Get only the name of the map if it's a workshop map
	if (StrContains(g_srThisServer.sServerMap, "workshop/", false) != -1)
		GetCurrentWorkshopMap(g_srThisServer.sServerMap, sizeof(g_srThisServer.sServerMap));
	
	// After everything we couldn't get the IP32, so we have no point to continue
	if((g_srThisServer.iServerIP32 = GetServerIP32()) == 0)
		SetFailState("%s Couldn't get the server IP", PREFIX_NO_COLOR);
	
	// Get the server Max-Players
	g_srThisServer.iMaxPlayers = GetMaxHumanPlayers();
	
	// If reserved slots is used, lets take it to count.
	if(g_cvReservedSlots)
		g_srThisServer.iReservedSlots = g_cvReservedSlots.IntValue;
	
	if(g_cvHiddenSlots)
		g_srThisServer.bHiddenSlots = g_cvHiddenSlots.BoolValue;
	
	// Get the server Port
	g_srThisServer.iServerPort = GetConVarInt(FindConVar("hostport"));
	
	// Get the server Player-Count
	g_srThisServer.iNumOfPlayers = GetClientCountEx(g_srThisServer.bIncludeBots);
	
	// Set the server status to online.
	g_srThisServer.bServerStatus = true;
	
	if (g_cvPrintDebug.BoolValue)
	{
		char iIP[4][4];
		GetIPv4FromIP32(g_srThisServer.iServerIP32, iIP);
		LogMessage("Name - %s\nCategory - %s\nIP32 - %d\nIP - %s.%s.%s.%s\nPort - %d\nMap - %s\nNumber of players - %d\nMax Players - %d\nshow server - %b", 
			g_srThisServer.sServerName,
			g_srThisServer.sServerCategory,
			g_srThisServer.iServerIP32,
			iIP[0], iIP[1], iIP[2], iIP[3],
			g_srThisServer.iServerPort,
			g_srThisServer.sServerMap,
			g_srThisServer.iNumOfPlayers,
			g_srThisServer.iMaxPlayers,
			g_srThisServer.bShowInServerList
		);
	}
}

any[] GetServerByIndex(int index)
{
	static Server srServer;
	g_hOtherServers.GetArray(index, srServer, sizeof(srServer));
	
	return srServer;
}

any[] GetAdvertisementByIndex(int index)
{
	static Advertisement advAdvertisement;
	g_hAdvertisements.GetArray(index, advAdvertisement, sizeof(advAdvertisement));
	
	return advAdvertisement;
}

// From smlib: https://github.com/bcserv/smlib/blob/master/scripting/include/smlib/strings.inc#L185-L233   -  Thanks :)
// Translated to new syntax by me.

/**
 * Checks if string str starts with subString.
 * 
 *
 * @param str				String to check
 * @param subString			Sub-String to check in str
 * @return					True if str starts with subString, false otherwise.
 */
bool String_StartsWith(const char[] str, const char[] subString)
{
	int n = 0;
	while (subString[n] != '\0')
	{
		if (str[n] == '\0' || str[n] != subString[n])
			return false;
			
		n++;
	}

	return true;
}

/* TODO:
* This Release:
* 1. [✓] Add an option to delete a sever from the database. (insted added a "time-out" so servers that didn't got updated in x min will get deleted) 
* 3. [✓] Add reserve slot support for the player-count.
* 2. [✗] Add an option to show / hide certian servers.
* 4. [✗] Multi-Select for advertisements
* 5. [✗] Add to servers table struct the Account-ID so we identify the server automaticlly
*
* Later Releases:
* 1. [✗] Make the plugin more dynamic and use arraylist so i wont have to use fixed arrays
* 2. [✗] Party mod :P
*
* 
*/

/* What was added? [Version 2.3.0 Changelog]
* 1. Advertisements! (formatable messages, Map-Change message, Player-Range message, do / don't Advertise offline servers)
* 2. Auto Time-Out server deletion.
* 3. Config instead of the old ConVars
* 4. Control over Commands that open the Server-List.
* 5. Prefix Remover
* 6. ERROR FIX for the map start invalid database handle (and maybe crashes?)
* 7. File is now lighter, removed the 'smlib' include and took only 2 things i needed
* 8. Added reserve slot support, override command 'server_redirect_use_reserved_slots' or ROOT admin-flag can see reserved slots.
* 9. FIX ServerList menu glitching out and not showing part of the servers / next / back buttons.
* 10. Too many connections to the DB server FIX :)
*
*/