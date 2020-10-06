#include <steamworks>
#include <redirect_core>
#include <multicolors>
#include <ServerRedirect>

#pragma newdecls required
#pragma semicolon 1

// PREFIXs for the menus and chat messages
#define PREFIX " \x04[Server-Redirect+]\x01"
#define PREFIX_NO_COLOR "[Server-Redirect+]"

// Config file path
#define SETTINGS_PATH "configs/ServerRedirect/Config.cfg"

// Lenght as used in the Database.
#define MAX_SERVER_NAME_LENGHT 245
#define MAX_CATEGORY_NAME_LENGHT 32

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
ConVar 	g_cvSvPassword;							// Server password.

bool 	g_bShowServerOnServerList; 				// Show this server in the Server-List?
bool 	g_bAdvertisementsAreEnabled; 			// Should we advertise servers?

char 	g_sServerListCommands[256];				// Commands for the Server-List.
char 	g_sMenuFormat[256]; 					// Menu Server Format
char 	g_sPrefixRemover[128]; 					// String to remove from the server name (useful for removing prefixs)

int 	g_iServerTimeOut;						// The amount of time before this server will be deleted from the database after the last update

//======[ Settings Related ]====//
Regex rgCountStrings;

//======[ UPDATE ADV ARR ]=====//
int g_iUpdateAdvProprietary[MAXPLAYERS + 1] =  { UPDATE_NOTHING, ... };

//=======[ SERVER STRUCT ]======//
enum struct Server
{
	ArrayList hCategories;
	
	char sName[MAX_SERVER_NAME_LENGHT];
	char sPass[PLATFORM_MAX_PATH];
	char sMap[PLATFORM_MAX_PATH];
	
	int iReservedSlots;
	int iNumOfPlayers;
	int iMaxPlayers;
	int iSteamAID;
	int iBackupID;
	int iPort;
	int iP32;
	
	bool bShowInServerList;
	bool bHiddenSlots;
	bool bIncludeBots;
	bool bStatus;
	
	void Init()
	{
		this.Close();
		
		this.hCategories = new ArrayList(ByteCountToCells(MAX_CATEGORY_NAME_LENGHT));
	}
	
	void Close()
	{
		if(this.hCategories)
			delete this.hCategories;
	}
	
	bool IsTimedOut(DBResultSet results)
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.IsTimedOut() | iSteamAID = %d", this.iSteamAID);
		
		int iServerTimeOut = results.FetchInt(SQL_FIELD_TIMEOUT) * 60;
		if(iServerTimeOut > 0)
		{
			int iServerLastUpdate 		 = results.FetchInt(SQL_FIELD_LAST_UPDATE_UNIX);
			int iServerTimeWithoutUpdate = GetTime() - iServerLastUpdate;
			
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Deleting Server (Server Steam ID - %d | Last update - %d | timeout time in sec - %d | time without update %d)",
					this.iSteamAID,
					iServerLastUpdate,
					iServerTimeOut,
					iServerTimeWithoutUpdate
				);
				
			return (iServerTimeWithoutUpdate >= iServerTimeOut);
		}
		
		return false;
	}
	
	void AddCategoriesToDB()
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.AddCategoriesToDB()");
		
		if(!this.hCategories.Length)
			return;
		
		strcopy(Query, sizeof(Query), "INSERT INTO `server_redirect_categories` (`name`, `associated_server_steam_id`) VALUES");
		
		char sCategory[MAX_CATEGORY_NAME_LENGHT];
		for (int iCurrentCategory = 0; iCurrentCategory < this.hCategories.Length; iCurrentCategory++)
		{
			this.hCategories.GetString(iCurrentCategory, sCategory, MAX_CATEGORY_NAME_LENGHT);
			Format(Query, sizeof(Query), "%s ('%s', %d)%s", Query, sCategory, this.iSteamAID, iCurrentCategory != this.hCategories.Length - 1 ? ", " : ";");
		}
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Server.AddCategoriesToDB(): %s", Query);
		
		DB.Query(T_FakeFastQuery, Query);
	}
	
	void DeleteCategoriesFromDB(int iOldSteadAID = -1)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.DeleteCategoriesFromDB()");
		
		Format(Query, sizeof(Query), "DELETE FROM `server_redirect_categories` WHERE `associated_server_steam_id` = %d", (iOldSteadAID == -1) ? this.iSteamAID : iOldSteadAID);
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Server.DeleteCategoriesFromDB(): %s", Query);
		
		DB.Query(T_FakeFastQuery, Query);
	}
	
	void UpdateCategoriesInDB()
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.UpdateCategoriesInDB()");
		
		this.DeleteCategoriesFromDB();
		this.AddCategoriesToDB();
	}
	
	void DeleteFromDB()
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.DeleteFromDB()");
		
		Format(Query, sizeof(Query), "DELETE FROM `server_redirect_servers` WHERE `steam_id` = %d", this.iSteamAID);
					
		if (g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Server.DeleteFromDB(): %s", Query);
	
		DB.Query(T_FakeFastQuery, Query, _, DBPrio_Low);
		
		this.DeleteCategoriesFromDB();
	}
	
	// Registering a new server in the Database server.
	void Register()
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.Register()");
		
		DB.Format(Query, sizeof(Query), "INSERT INTO `server_redirect_servers` (`backup_id`, `steam_id`, `name`, `password`, `ip`, `port`, `status`, `map`, `number_of_players`, `max_players`, `reserved_slots`, `hidden_slots`, `is_visible`, `timeout_time`) VALUES (%d, %d, '%s', '%s', %d, %d, %d, '%s', %d, %d, %d, %d, %b, %d)", 
			this.iBackupID,
			this.iSteamAID,
			this.sName,
			this.sPass,
			this.iP32,
			this.iPort,
			this.bStatus,
			this.sMap,
			this.iNumOfPlayers,
			this.iMaxPlayers,
			this.iReservedSlots,
			this.bHiddenSlots,
			this.bShowInServerList,
			g_iServerTimeOut
		);
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Server.Register(): %s", Query);
		
		DB.Query(T_FakeFastQuery, Query, _, DBPrio_High);
		
		this.AddCategoriesToDB();
	}
	
	// Updating the server information based of the sent parameter.
	void UpdateInDB(int iWhatToUpdate, DBPriority dbPriority = DBPrio_Normal)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.UpdateInDB() | iWhatToUpdate = %d", iWhatToUpdate);
		
		// TODO: Easy formatting, testing needed:
		// Each UPDATE_TYPE will have a string and will be formatted in this template:
		//Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET {CHANGE} WHERE `steam_id` = %d")
		
		switch (iWhatToUpdate)
		{
			case UPDATE_SERVER_STEAM_ID:
			{
				Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `steam_id` = %d WHERE `backup_id` = %d",
					this.iSteamAID,
					this.iBackupID
				);
			}
			case UPDATE_SERVER_PLAYERS:
			{
				// Get Client-Count
				Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `number_of_players` = %d WHERE `steam_id` = %d",
					this.iNumOfPlayers,
					this.iSteamAID
				);
			}
			case UPDATE_SERVER_STATUS:
			{
				Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `status` = %d WHERE `steam_id` = %d",
					this.bStatus,
					this.iSteamAID
				);
			}
			case UPDATE_SERVER_START:
			{
				this.UpdateCategoriesInDB();
				
				DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `name` = '%s', `password` = '%s', `ip` = %d, `port` = %d, `status` = %d, `is_visible` = %d, `max_players` = %d, `reserved_slots` = %d, `hidden_slots` = %b, `bots_included` = %b, `map` = '%s', `timeout_time` = %d WHERE `steam_id` = %d",
					this.sName,
					this.sPass,
					this.iP32,
					this.iPort,
					this.bStatus,
					this.bShowInServerList,
					this.iMaxPlayers,
					this.iReservedSlots,
					this.bHiddenSlots,
					this.bIncludeBots,
					this.sMap,
					g_iServerTimeOut,
					this.iSteamAID
				);
			}
		}
		if (g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Server.UpdateInDB(): %s", Query);
		
		DB.Query(T_FakeFastQuery, Query, _, dbPriority);
	}
	
	void UpdateServerAdvertisements(int iOutdatedServerSteamAID)
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.DeleteFromDB() | iSteamAID = %d (Outdated: %d)", this.iSteamAID, iOutdatedServerSteamAID);
		
		Format(Query, sizeof(Query), "UPDATE `server_redirect_advertisements` SET `advertised_server` = %d WHERE `advertised_server` = %d", this.iSteamAID, iOutdatedServerSteamAID);
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Server.UpdateServerAdvertisements() | advertised_server: %s", Query);
		
		DB.Query(T_FakeFastQuery, Query);
		
		Format(Query, sizeof(Query), "UPDATE `server_redirect_advertisements` SET `advertising_server` = %d WHERE `advertising_server` = %d", this.iSteamAID, iOutdatedServerSteamAID);
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Server.UpdateServerAdvertisements() | advertising_server: %s", Query);
		
		DB.Query(T_FakeFastQuery, Query);
	}
	
	void AddCategory(const char[] sCategory)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Server.AddCategory() | Category Name: %s", sCategory);
		
		this.hCategories.PushString(sCategory);
	}
	
	void DebugPrint_Categories()
	{
		char sCategory[MAX_CATEGORY_NAME_LENGHT];
		
		PrintToChatAll("%s '%s' Categories:", PREFIX, this.sName);
		
		for (int iCurrentCategory = 0; iCurrentCategory < this.hCategories.Length; iCurrentCategory++)
		{
			this.hCategories.GetString(iCurrentCategory, sCategory, sizeof(sCategory));
			PrintToChatAll("[%d] %s", iCurrentCategory, sCategory);
		}
	}
	
	bool IsGlobal()
	{
		return this.InCategory("GLOBAL");
	}
	
	bool InCategory(const char[] sCategory)
	{
		return (this.hCategories.FindString(sCategory) != -1);
	}
	
	void GetCategoryName(int index, char[] sBufferToStoreIn, int iBufferSize)
	{
		this.hCategories.GetString(index, sBufferToStoreIn, iBufferSize);
	}
}
ArrayList g_hOtherServers;
Server g_srThisServer;

//=====[ ADVERTISEMENT ENUM ]===//
enum struct Advertisement
{
	int iPlayersRange[2]; 	// 0 - MIN | 1 - MAX
	
	int iAdvertisedServer;	// Advertised Server
	int iAdvertisedTime;	// Used for calculating if the advertisement should post
	int iCoolDownTime;		// How long should this advertisement should be on cooldown (for 'deffrence check' advertisements)
	int iRepeatTime;		// How long to wait between each advertise
	int iAdvID;				// Advertisement ID
	
	char sMessage[512];		// Message to print
	
	bool bActive;			// If the advertisement is currently active
	
	void Reset()
	{
		this.iPlayersRange = {0, 0};
		
		this.iAdvertisedServer 	= 0;
		this.iAdvertisedTime 	= 0;
		this.iCoolDownTime 		= 0;
		this.iRepeatTime 		= 0;
		this.iAdvID 			= 0;
		
		this.sMessage = "";
		
		this.bActive = false;
	}
	
	void DeleteFromDB()
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Advertisement.DeleteFromDB() | iAdvID = %d", this.iAdvID);	
	
		Format(Query, sizeof(Query), "DELETE FROM `server_redirect_advertisements` WHERE `id` = %d", this.iAdvID);	
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Advertisement.DeleteFromDB(): %s", Query);
		
		DB.Query(T_UpdateAdvertisementQuery, Query, false);
	}
	
	int UpdateOnDB()
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Advertisement.UpdateOnDB() | iAdvID = %d", this.iAdvID);
		
		char sPlayersRange[6];
		Format(sPlayersRange, sizeof(sPlayersRange), "%d|%d", this.iPlayersRange[0], this.iPlayersRange[1]);
		
		DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_advertisements` SET `advertised_server` = %d, `repeat_time` = %d, `cooldown_time` = %d, `players_range` = '%s', `message` = '%s' WHERE `id` = %d",
			this.iAdvertisedServer,
			this.iRepeatTime,
			this.iCoolDownTime,
			sPlayersRange,
			this.sMessage,
			this.iAdvID
		);
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Advertisement.UpdateOnDB(): %s", Query);
		
		DB.Query(T_UpdateAdvertisementQuery, Query, false);
		
		return ADV_ACTION_UPDATE;
	}
	
	int AddToDB()
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage(" <-- Advertisement.AddToDB() | iAdvID = %d", this.iAdvID);
		
		char sPlayersRange[6];
		Format(sPlayersRange, sizeof(sPlayersRange), "%d|%d", this.iPlayersRange[0], this.iPlayersRange[1]);
		
		DB.Format(Query, sizeof(Query), "INSERT INTO `server_redirect_advertisements`(`advertising_server`, `advertised_server`, `repeat_time`, `cooldown_time`, `message`, `players_range`) VALUES (%d, %d, %d, %d, '%s', '%s')",
			g_srThisServer.iSteamAID,
			this.iAdvertisedServer,
			this.iRepeatTime,
			this.iCoolDownTime,
			this.sMessage,
			sPlayersRange
		);
		
		if(g_cvPrintDebug.BoolValue)
			LogMessage("[Query] Advertisement.AddToDB(): %s", Query);
		
		DB.Query(T_UpdateAdvertisementQuery, Query);
		
		return ADV_ACTION_EDIT;
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
	version = "3.0.1", 
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
	HookEvent("server_spawn", Event_ServerSpawn, EventHookMode_Post);
	
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
	g_cvSvPassword	  = FindConVar("sv_password"		);
	
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
		LogMessage(" <-- OnClientPostAdminCheck | client =  %N (%d)", client, client);
	
	// Check if the client is a bot and if the server doesn't want to take bots into account (continue if the client is not fake)
	// Yes: Starting the update Player-Count timer.
	if (!IsFakeClient(client) || g_srThisServer.bIncludeBots)
	{
		g_srThisServer.iNumOfPlayers = GetClientCountEx(g_srThisServer.bIncludeBots);
		
		StartUpdateTimer();
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Next update will be in %d seconds.", g_cvUpdateServerInterval.IntValue);
	}
}

// OnClientDisconnect Will start the Server-Update timer if it's not already running.
public void OnClientDisconnect(int client)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnClientDisconnect | client = %N (%d)", client, client);
	
	// Check if the client is a bot and if the server doesn't want to take bots into account (continue if the client is not fake)
	// Yes: Starting the update Player-Count timer.
	if (!IsFakeClient(client) || g_srThisServer.bIncludeBots)
	{
		// Get the server Player-Count.
		g_srThisServer.iNumOfPlayers = GetClientCountEx(g_srThisServer.bIncludeBots) - 1;
		
		if (g_cvPrintDebug.BoolValue)
				LogMessage("Number of remaining clients - %d", g_srThisServer.iNumOfPlayers);
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Update will be sent %s", (g_srThisServer.iNumOfPlayers != 0) ? "After the timer" : "Now");
		
		StartUpdateTimer(!g_srThisServer.iNumOfPlayers);
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
	if(g_srThisServer.iBackupID > 0)
	{
		g_srThisServer.bStatus = false;
		g_srThisServer.UpdateInDB(UPDATE_SERVER_STATUS);
	}
	else
	{
		Format(Query, sizeof(Query), "DELETE FROM `server_redirect_servers` WHERE `steam_id` = %d", g_srThisServer.iSteamAID);
		DB.Query(T_FakeFastQuery, Query, _, DBPrio_High);
	}
}

//==================================[ TIMERS ]==============================//

// Main Timer for the Advertisements and updating the player count.
Action Timer_Loop(Handle timer)
{
	#pragma unused timer
	
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
			
			// If the advertisement is a LOOP type AND this is the time to post the advertisement, go for it.
			if(advCurrentAdvertisement.iRepeatTime > ADVERTISEMENT_LOOP && g_iTimerCounter % advCurrentAdvertisement.iRepeatTime == 0)
				PostAdvertisement(advCurrentAdvertisement.iAdvertisedServer, ADVERTISEMENT_LOOP, iCurrentAdvertisement);
		}
	}
	
	return Plugin_Continue;
}

// After the Update-Interval time has passed, updae the server.
Action Timer_UpdateServerInDatabase(Handle timer)
{
	#pragma unused timer
	
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
		DB.Query(T_FakeFastQuery, "CREATE TABLE IF NOT EXISTS `server_redirect_categories` (`name` VARCHAR(32) NOT NULL, \
																							`associated_server_steam_id` INT NOT NULL, \
																							PRIMARY KEY (`name`, `associated_server_steam_id`))",
																							_, DBPrio_High);
		
		DB.Query(T_OnDatabaseReady, "CREATE TABLE IF NOT EXISTS `server_redirect_servers` ( `id` INT NOT NULL AUTO_INCREMENT, \
																							`backup_id` INT NOT NULL, \
																							`steam_id` INT NOT NULL, \
																							`name` VARCHAR(245) NOT NULL, \
																							`password` VARCHAR(256) NOT NULL, \
																							`ip` INT NOT NULL DEFAULT '-1', \
																							`port` INT NOT NULL DEFAULT '0', \
																							`status` INT NOT NULL DEFAULT '0', \
																							`is_visible` INT NOT NULL DEFAULT '1', \
																							`map` VARCHAR(64) NOT NULL, \
																							`number_of_players` INT NOT NULL DEFAULT '0', \
																							`reserved_slots` INT NOT NULL DEFAULT '0', \
																							`hidden_slots` INT(1) NOT NULL DEFAULT '0', \
																							`max_players` INT NOT NULL DEFAULT '0', \
																							`bots_included` INT NOT NULL DEFAULT '0', \
																							`unix_lastupdate` TIMESTAMP on update CURRENT_TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
																							`timeout_time` INT NOT NULL DEFAULT '0', \
																							PRIMARY KEY (`id`), UNIQUE(`steam_id`))",
																							_, DBPrio_High);
	}
}

// Now the database is ready and we have a valid table to work with.
void T_OnDatabaseReady(Database owner, DBResultSet results, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnDatabaseReady");
	
	if (results != INVALID_HANDLE)
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
	
	Format(Query, sizeof(Query), "SELECT `steam_id` FROM `server_redirect_servers` WHERE `%s` = %d",
		(!iSearchBy) ? "steam_id" : "backup_id",
		(!iSearchBy) ? g_srThisServer.iSteamAID : g_srThisServer.iBackupID);
		
	if (g_cvPrintDebug.BoolValue)
		LogMessage("[Query] FindServer(): %s", Query);
	
	DB.Query(T_OnServerSearchResultsReceived, Query, iSearchBy, DBPrio_High);
}

void T_OnServerSearchResultsReceived(Database owner, DBResultSet results, const char[] sError, any iSearchBy)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnServerSearchResultsReceived");
	
	if (results != INVALID_HANDLE)
	{
		// If the row is fetched, that means we found the server. No rows = server doesn't exit in the DB.
		if(results.FetchRow())
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Found Server %s-ID - %d", (iSearchBy == SERVER_SEARCH_BY_STEAM_ID) ? "Steam" : "Backup", (iSearchBy == SERVER_SEARCH_BY_STEAM_ID) ? g_srThisServer.iSteamAID : g_srThisServer.iBackupID);
			
			// If we found the server Backup-ID after not finding by Steam-ID, update the Steam-ID
			if(iSearchBy == SERVER_SEARCH_BY_BACKUP_ID)
			{
				// Get the old SteamID
				int iOutdatedServerSteamID = results.FetchInt(0);
				
				// Update advertisements (Change old Server Steam-ID to the new one)
				g_srThisServer.UpdateServerAdvertisements(iOutdatedServerSteamID);
				
				// Delete Old Categories
				g_srThisServer.DeleteCategoriesFromDB(iOutdatedServerSteamID);
				
				// Update the new Steam-ID
				g_srThisServer.UpdateInDB(UPDATE_SERVER_STEAM_ID, DBPrio_High);
			}
			
			// Update the server.
			g_srThisServer.UpdateInDB(UPDATE_SERVER_START, DBPrio_Normal);
		}
		else 
		{
			// If the server wansn't found with the SteamAID and there is a valid Backup-ID, try recovering it.
			if(iSearchBy == SERVER_SEARCH_BY_STEAM_ID && g_srThisServer.iBackupID > 0)
			{
				if (g_cvPrintDebug.BoolValue)
					LogMessage("Couldn't find any servers with this Steam-ID (%d), Searching for the Server Backup-ID", g_srThisServer.iSteamAID);
				
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
void T_FakeFastQuery(Database owner, DBResultSet results, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_FakeFastQuery");
	
	if (results == INVALID_HANDLE)
		LogError("Error in T_FakeFastQuery: %s", sError);
}

//==================================[ HELPING ]==============================//
void PluginStartUpProccess()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- PluginStartUpProccess");
	
	// Load Settings from the config
	LoadSettings();
	
	// Loading the Database
	LoadDB();
	
	// Starting the loop timer
	CreateTimer(1.0, Timer_Loop, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
	g_srThisServer.iBackupID = kvSettings.GetNum("ServerBackupID", 0);
	
	g_srThisServer.iSteamAID = GetServerSteamAccountId();
		
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Server Steam Accound-ID: %d", g_srThisServer.iSteamAID);
	
	// If we don't have the server steam account id and we didn't got a ServerID ask for a manual configuration.
	if(g_srThisServer.iSteamAID == 0)
		SetFailState("Couldn't get the Server Steam Account ID, please make sure the server is using a valid token!");
	
	// Get the rest of the settings if everything is ok
	g_srThisServer.bShowInServerList = view_as<bool>(kvSettings.GetNum("ShowSeverInServerList"	, 1));
	g_srThisServer.bIncludeBots 	 = view_as<bool>(kvSettings.GetNum("ShowBots"				, 0));
	g_bAdvertisementsAreEnabled 	 = view_as<bool>(kvSettings.GetNum("EnableAdvertisements"	, 1));
	
	g_iServerTimeOut = kvSettings.GetNum("ServerTimeOut", 1440);
	
	kvSettings.GetString("MenuFormat"			, g_sMenuFormat						, sizeof(g_sMenuFormat)						);
	kvSettings.GetString("PrefixRemover"		, g_sPrefixRemover					, sizeof(g_sPrefixRemover)					);
	kvSettings.GetString("ServerName"			, g_srThisServer.sName				, sizeof(g_srThisServer.sName)				);
	
	g_srThisServer.Init();
	
	// Add all commands
	if(kvSettings.JumpToKey("ServerListCommands"))
	{
		char sCommand[128];
		
		if(kvSettings.GotoFirstSubKey(false))
		{
			do
			{
				kvSettings.GetString(NULL_STRING, sCommand, sizeof(sCommand));
				
				if(!StrEqual(sCommand, "") && !CommandExists(sCommand))
					RegConsoleCmd(sCommand, Command_ServerList, "Opens the Server-List Menu.");
				
			} while (kvSettings.GotoNextKey(false));
			
			kvSettings.GoBack();
		}
		
		kvSettings.GoBack();
	}
	
	// Add all categories
	if(kvSettings.JumpToKey("ServerCategories"))
	{
		char sCategoryName[MAX_CATEGORY_NAME_LENGHT];
		
		if(kvSettings.GotoFirstSubKey(false))
		{
			do
			{
				kvSettings.GetString("name", sCategoryName, sizeof(sCategoryName));
				g_srThisServer.AddCategory(sCategoryName);
				
			} while (kvSettings.GotoNextKey());
		}
	}
	
	kvSettings.Close();
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Settings Loaded:\nServerBackupID: %d\nMenuFormat: %s\nServerListCommands: %s\nServerName: %s\nShowBots: %d\nShowSeverInServerList: %d",
			g_srThisServer.iSteamAID,
			g_sMenuFormat,
			g_sServerListCommands,
			g_srThisServer.sName,
			g_srThisServer.bIncludeBots,
			g_bShowServerOnServerList
		);
}

// Starting the server update timer if it's not already running.
void StartUpdateTimer(bool bSkipTimerAndUpdate = false)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- StartUpdateTimer | ServerUpdateTimer %s", g_hServerUpdateTimer ? "Already running" : "Started");
	
	// g_hServerUpdateTimer - FALSE | bSkipTimerAndUpdate - FALSE --> TIME
	// g_hServerUpdateTimer - TRUE 	| bSkipTimerAndUpdate - TRUE  --> STOP | NOW
	
	// g_hServerUpdateTimer - FALSE | bSkipTimerAndUpdate - TRUE  --> NOW
	// g_hServerUpdateTimer - TRUE 	| bSkipTimerAndUpdate - FALSE --> ----
	
	// If timer is not running.
	if (!g_hServerUpdateTimer) 
	{
		// Start the timer with the right time, 0 if we need it now, if not just the interval.
		g_hServerUpdateTimer = CreateTimer(bSkipTimerAndUpdate ? 0.0 : g_cvUpdateServerInterval.FloatValue, Timer_UpdateServerInDatabase);
	}
	// If the timer is running.
	else if(bSkipTimerAndUpdate)
	{
		// if the timer is running and we need to update now, kill the timer.
		if(bSkipTimerAndUpdate) 
			delete g_hServerUpdateTimer;
		
		// Starting the timer.
		CreateTimer(0.0, Timer_UpdateServerInDatabase);
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
	
	return iClientCount;
}

// Copying a string to it's destination and adding a '...' if the string isn't fully shown.
int CopyStringWithDots(char[] sDest, int iDestLen, char[] sSource)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage("<-- CopyStringWithDots | sSource - %s | length - %d", sSource, iDestLen);
	
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
	if (StrEqual(g_srThisServer.sName, "", false))
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Server name was empty. Getting the hostname.");
		
		GetConVarString(FindConVar("hostname"), g_srThisServer.sName, sizeof(g_srThisServer.sName));
	}
	
	// Get server map
	GetCurrentMap(g_srThisServer.sMap, sizeof(g_srThisServer.sMap));
	
	// Get only the name of the map if it's a workshop map
	if (StrContains(g_srThisServer.sMap, "workshop/", false) != -1)
		GetCurrentWorkshopMap(g_srThisServer.sMap, sizeof(g_srThisServer.sMap));
	
	// After everything we couldn't get the IP32, so we have no point to continue
	if((g_srThisServer.iP32 = GetServerIP32()) == 0)
		SetFailState("%s Couldn't get the server IP", PREFIX_NO_COLOR);
	
	// Get the server Max-Players
	g_srThisServer.iMaxPlayers = GetMaxHumanPlayers();
	
	// If reserved slots is used, lets take it to count.
	if(g_cvReservedSlots)
		g_srThisServer.iReservedSlots = g_cvReservedSlots.IntValue;
	
	if(g_cvHiddenSlots)
		g_srThisServer.bHiddenSlots = g_cvHiddenSlots.BoolValue;
	
	if(g_cvSvPassword)
		g_cvSvPassword.GetString(g_srThisServer.sPass, sizeof(g_srThisServer.sPass));
	
	// Get the server Port
	g_srThisServer.iPort = GetConVarInt(FindConVar("hostport"));
	
	// Get the server Player-Count
	g_srThisServer.iNumOfPlayers = GetClientCountEx(g_srThisServer.bIncludeBots);
	
	// Set the server status to online.
	g_srThisServer.bStatus = true;
	
	if (g_cvPrintDebug.BoolValue)
	{
		char iIP[4][4];
		GetIPv4FromIP32(g_srThisServer.iP32, iIP);
		LogMessage("Name - %s\nIP32 - %d\nIP - %s.%s.%s.%s\nPort - %d\nMap - %s\nNumber of players - %d\nMax Players - %d\nshow server - %b", 
			g_srThisServer.sName,
			g_srThisServer.iP32,
			iIP[0], iIP[1], iIP[2], iIP[3],
			g_srThisServer.iPort,
			g_srThisServer.sMap,
			g_srThisServer.iNumOfPlayers,
			g_srThisServer.iMaxPlayers,
			g_srThisServer.bShowInServerList
		);
	}
}

// Returning the server index given the server ID
int GetServerIndexByServerID(int iSteamAID)
{
	if (iSteamAID != 0)
	{
		for (int iCurrentServer = 0; iCurrentServer < g_hOtherServers.Length; iCurrentServer++)
			if(GetServerByIndex(iCurrentServer).iSteamAID == iSteamAID)
				return iCurrentServer;
	}
			
	return -1;
}

any[] GetServerByIndex(int index)
{
	Server srServer;
	g_hOtherServers.GetArray(index, srServer, sizeof(srServer));
	
	return srServer;
}

any[] GetAdvertisementByIndex(int index)
{
	Advertisement advAdvertisement;
	g_hAdvertisements.GetArray(index, advAdvertisement, sizeof(advAdvertisement));
	
	return advAdvertisement;
}

// From smlib: https://github.com/bcserv/smlib/blob/master/scripting/include/smlib/strings.inc#L185-L206   -  Thanks :)
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
* 2. [✓] Add reserve slot support for the player-count.
* 3. [✓] Make the plugin more dynamic and use arraylist so i wont have to use fixed arrays.
* 4. [✓] Add to servers table struct the Account-ID so we identify the server automaticlly.
* 5. [✗] Add an option to show / hide certian servers.
* 6. [✗] Multi-Select for advertisements
*
* Later Releases:
* 1. [✗] Party mod :P
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
* 11. 0.0.0.0 IP BUG resolved.
* 12. Plugin is now fully dynamic with arraylists.
* 13. Add a server to multiple categories.
*/