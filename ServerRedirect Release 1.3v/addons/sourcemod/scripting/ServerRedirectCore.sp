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

// Will be dynamic in the next version
#define MAX_SERVERS 50
#define MAX_ADVERTISEMENTS MAX_SERVERS * 4

//============[ DB ]============//
Database DB = null;								// Database handle
char Query[512];								// Query string for quering 

//=======[ Update Timer ]=======//
Handle g_hServerUpdateTimer = INVALID_HANDLE; 	// Update this server
Handle g_hOtherServersUpdateTimer;				// Update other servers
int g_iTimerCounter;							// Timer For Advertisements

//==========[ Settings ]=========//
ConVar 	g_cvUpdateOtherServersInterval; 		// Timer Interval for other servers update
ConVar 	g_cvUpdateServerInterval; 				// Time between each update
ConVar 	g_cvPrintDebug; 						// Debug Mode Status

ConVar 	g_cvReservedSlots;
ConVar 	g_cvHiddenSlots;

bool 	g_bShowServerOnServerList; 				// Show this server in the Server-List?
bool 	g_bEnableAdvertisements; 				// Should we advertise servers?
bool 	g_bAdvertiseOfflineServers; 			// Should we advertise offline servers?

char 	g_sServerListCommands[256];				// Commands for the Server-List.
char 	g_sMenuFormat[256]; 					// Menu Server Format
char 	g_sPrefixRemover[128]; 					// String to remove from the server name (useful for removing prefixs)

int 	g_iServerTimeOut;						// The amount of time before this server will be deleted from the database after the last update

//======[ Settings Related ]====//
Regex rgCountStrings;

//=====[ ADVERTISEMENT ENUM ]===//
enum struct Advertisement
{
	int iAdvID;					// Advertisement ID
	int iRepeatTime;			// How long to wait between each advertise
	int iCoolDownTime;			// How long should this advertisement should be on cooldown (for 'deffrence check' advertisements)
	int iAdvertisedTime;		// Used for calculating if the advertisement should post
	int iPlayersRange[2]; 		// 0 - MIN | 1 - MAX
	int iServerIDToAdvertise;	// Advertised Server
	
	char sMessageContent[512];	// Message to print
	
	bool bActive;				// If the advertisement is currently active
}
Advertisement g_advAdvertisements[MAX_ADVERTISEMENTS];	// All of the server advertisements
Advertisement g_advToEdit;								// For editing / adding the advertisements

//=======[ ADV TYPE ENUM ]======//
enum
{
	ADVERTISEMENT_LOOP		 	=  0, // USING TIMER
	ADVERTISEMENT_MAP 		 	= -1, // USING DEFFRENCE CHECK
	ADVERTISEMENT_PLAYERS_RANGE = -2  // USING DEFFRENCE CHECK
}

//======[ UPDATE ADV ENUM ]=====//
enum
{
	UPDATE_NOTHING 			= -1,	// Updating nothing
	UPDATE_LOOP_TIME 		=  0,	// Updating Loop time
	UPDATE_COOLDOWN_TIME 	=  1,	// Updating Cooldown time
	UPDATE_PLAYER_RANGE 	=  2,	// Updating player range
	UPDATE_ADV_MESSAGE 		=  3	// Updating message string
}
int g_iUpdateAdvProprietary[MAXPLAYERS + 1] =  { UPDATE_NOTHING, ... };

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
	int iServerID;
	
	bool bShowInServerList;
	bool bServerStatus;
	bool bHiddenSlots;
	bool bIncludeBots;
}
Server g_srCurrentServer;
Server g_srOtherServers[MAX_SERVERS];

//======[ DB UPDATE ENUM ]======//
enum
{
	UPDATE_SERVER_PLAYERS, 
	UPDATE_SERVER_STATUS, 
	UPDATE_SERVER_START
}

//=========[ INCLUDES ]=========//
#include "ServerRedirectMenus.sp"
#include "ServerRedirectAdvertisements.sp"

//=======[ PLUGIN INFO ]========//
public Plugin myinfo = 
{
	name = "[Server-Redirect+] Core", 
	author = "Natanel 'LuqS'", 
	description = "Core of 'Server-Redirect+', gathering information about the server and sending it to the SQL Database.", 
	version = "2.3.0.0_Public", 
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
	HookEvent("server_shutdown", Event_ServerShutDown, EventHookMode_Pre);
	
	//==========================[ ADMIN COMMANDS ]======================//
	RegAdminCmd("sm_editsradv", Command_EditServerRedirectAdvertisements, ADMFLAG_ROOT, "Edit server Advertisements");
	
	//==========================[ Console-Vars ]========================//
	g_cvUpdateOtherServersInterval 	= CreateConVar("server_redirect_other_servers_update_interval"	, "20.0", "The number of seconds between other servers update."											, _, true, 5.0, true, 600.0	);
	g_cvUpdateServerInterval 		= CreateConVar("server_redirect_server_update_interval"			, "20.0", "The number of seconds the plugin will wait before updating player count in the SQL server." 	, _, true, 0.0, true, 600.0	);
	g_cvPrintDebug 					= CreateConVar("server_redirect_debug_mode"						, "0"	, "Whether or not to print debug messages in server console"									, _, true, 0.0, true, 1.0	);
	
	g_cvReservedSlots = FindConVar("sm_reserved_slots"	);
	g_cvHiddenSlots	  = FindConVar("sm_hide_slots"		);
	
	//========================[ CVAR Change Hooks ]=====================//
	g_cvUpdateOtherServersInterval.AddChangeHook(OnCvarChange);
	
	//=========================[ AutoExec Config ]======================//
	AutoExecConfig(true);
	
	//========================[ Load Translations ]=====================//
	LoadTranslations("server_redirect.phrases");
	
	// Load Settings from the config
	LoadSettings();

	// Load the Server-List commands from the convar / config
	LoadServerListCommands();
}

// We are getting the Server info here because some things are invalid before,
// And we must load the database only after we know we have everyting to send.
public void OnMapStart()
{
	// Get Server info to send to the database
	GetServerInfo();
	
	// Loading the Database
	LoadDB();
}

// OnClientConnected & OnClientDisconnect_Post Will start the Server-Update timer if it's not already running.
public void OnClientPostAdminCheck(int client)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnClientConnected | int client =  %d", client);
	
	// If the user doesn't want bots, don't enter here.
	if (!IsFakeClient(client) || g_srCurrentServer.bIncludeBots)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("%N is valid (bots: %b)", client, g_srCurrentServer.bIncludeBots);
		
		// Starting the update timer.
		StartUpdateTimer();
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Client connected, starting timer");
		
	}
	else if (g_cvPrintDebug.BoolValue)
		LogMessage("%N isn't valid (bots: %b)", client, g_srCurrentServer.bIncludeBots);
}

// OnClientConnected & OnClientDisconnect Will start the Server-Update timer if it's not already running.
public void OnClientDisconnect(int client)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnClientDisconnect | int client =  %d", client);
	
	// If the user doesn't want bots, don't enter here.
	if (!IsFakeClient(client) || g_srCurrentServer.bIncludeBots)
	{
		// Get the client count
		g_srCurrentServer.iNumOfPlayers = GetClientCountEx(g_srCurrentServer.bIncludeBots);
		
		// If this client wasn't the last player, start the update timer.
		if (g_srCurrentServer.iNumOfPlayers != 0)
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Client disconnected, starting timer");
			
			StartUpdateTimer();
		}
		else // If it was the last player update the player-count right away.
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Last player disconnected, killing timer and updating");
			
			// FIX for server hibernation
			if (g_hServerUpdateTimer != INVALID_HANDLE)
			{
				KillTimer(g_hServerUpdateTimer);
				g_hServerUpdateTimer = INVALID_HANDLE;
			}
			UpdateServer(UPDATE_SERVER_PLAYERS);
		}
	}
}

// Updating the needed stuff when Con-Var is getting changed. //
public void OnCvarChange(ConVar cVar, char[] oldValue, char[] newValue)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnCvarChange");
	
	// Kill the old timer, we don't need him anymore.
	KillTimer(g_hOtherServersUpdateTimer);
	
	// Start a new timer with the updated interval.
	g_hOtherServersUpdateTimer = CreateTimer(StringToFloat(newValue), Timer_UpdateOtherServers, _, TIMER_REPEAT);
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Started OtherServersUpdateTimer (%.2f)", StringToFloat(newValue));
}

// Updating the Server-Status in the SQL server before shut-down.
public Action Event_ServerShutDown(Event event, const char[] name, bool dontBroadcast)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Event_ServerShutDown");
	
	// If the plugin is getting unloaded, probably the server is off so we want to update the server status in the database.
	g_srCurrentServer.bServerStatus = false;
	UpdateServer(UPDATE_SERVER_STATUS);
}

// Updating the Server-Status in the SQL server before plugin unload.
public void OnPluginEnd()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnPluginEnd");
	
	// If the plugin is getting unloaded, probably the server is off so we want to update the server status in the database.
	g_srCurrentServer.bServerStatus = false;
	UpdateServer(UPDATE_SERVER_STATUS);
}

//==================================[ TIMERS ]==============================//
// After the Update-Interval time has passed, updae the server.
public Action Timer_UpdateServerInDatabase(Handle timer)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Timer_UpdateServerInDatabase");
	
	// Get Client-Count
	g_srCurrentServer.iNumOfPlayers = GetClientCountEx(g_srCurrentServer.bIncludeBots);
	
	// Update on the database
	UpdateServer(UPDATE_SERVER_PLAYERS);
	
	// Set the timer back to INVALID_HANDLE
	g_hServerUpdateTimer = INVALID_HANDLE;
}

//==================================[ DB-STUFF ]==============================//
// Loading the Database config from sourcemod/configs/databases.cfg, checking if the table existes and if not creating a new one.
stock void LoadDB(bool bOnlyConnect = false)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadDB | bOnlyConnect = %b", bOnlyConnect);
	
	// Connect to the database
	Database.Connect(T_OnDBConnected, "ServerRedirect", bOnlyConnect);
}

// When we got a response from the db and we either connected or not.
public void T_OnDBConnected(Database dbMain, const char[] sError, any bOnlyConnect)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnDBConnected");
	
	if (dbMain == null) // Oops, something went wrong :S
		SetFailState("%s Cannot Connect To MySQL Server! | Error: %s", PREFIX_NO_COLOR, sError);
	else
	{
		// Save the database globally to send queries :D
		DB = dbMain;
		
		// Should the database only connect or also continue to the startup process
		if(bOnlyConnect)
			return;
		
		DB.Query(T_OnDatabaseReady, "CREATE TABLE IF NOT EXISTS server_redirect_servers (`id` INT NOT NULL AUTO_INCREMENT, `server_id` INT NOT NULL, `server_name` VARCHAR(245) NOT NULL, `server_category` VARCHAR(64) NOT NULL, `server_ip` INT NOT NULL, `server_port` INT NOT NULL, `server_status` INT NOT NULL, `server_visible` INT NOT NULL, `server_map` VARCHAR(64) NOT NULL, `number_of_players` INT NOT NULL, `reserved_slots` INT NOT NULL DEFAULT '0', `hidden_slots` INT(1) NOT NULL DEFAULT '0', `max_players` INT NOT NULL, `bots_included` INT NOT NULL, `unix_lastupdate` TIMESTAMP NOT NULL, `timeout_time` INT NOT NULL, PRIMARY KEY (`id`), UNIQUE(`server_id`))", _, DBPrio_High);
		CreateAdvertisementsTable();
	}
}

// Now the database is ready and we have a valid table to work with.
public void T_OnDatabaseReady(Handle owner, Handle hQuery, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnDatabaseReady");
	
	if (hQuery != INVALID_HANDLE)
	{
		// Send info to the database
		UpdateServerInfo();
		
		// Load all other servers
		LoadServers();
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Started g_hOtherServersUpdateTimer (%.2f)", g_cvUpdateOtherServersInterval.FloatValue);
			
		g_hOtherServersUpdateTimer = CreateTimer(g_cvUpdateOtherServersInterval.FloatValue, Timer_UpdateOtherServers, _, TIMER_REPEAT);
	}
	else
		LogError("Error in T_OnDatabaseReady: %s", sError);
}

// Updating the server information based of the sent parameter.
stock void UpdateServer(int iWhatToUpdate, DBPriority dbPriority = DBPrio_Normal)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- UpdateServer | int iWhatToUpdate = %d", iWhatToUpdate);
	
	switch (iWhatToUpdate)
	{
		case UPDATE_SERVER_PLAYERS:
		{
			Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `number_of_players` = %d WHERE `server_id` = %d",
			g_srCurrentServer.iNumOfPlayers,
			g_srCurrentServer.iServerID
			);
		}
		case UPDATE_SERVER_STATUS:
		{
			Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `server_status` = %d WHERE `server_id` = %d",
			g_srCurrentServer.bServerStatus,
			g_srCurrentServer.iServerID
			);
		}
		case UPDATE_SERVER_START:
		{
			DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `server_name` = '%s', `server_ip` = %d, `server_port` = %d, `server_status` = %d, `server_visible` = %d, `max_players` = %d, `reserved_slots` = %d, `hidden_slots` = %b, `bots_included` = %b, `server_map` = '%s', `timeout_time` = %d WHERE `server_id` = %d",
			g_srCurrentServer.sServerName,
			g_srCurrentServer.iServerIP32,
			g_srCurrentServer.iServerPort,
			g_srCurrentServer.bServerStatus,
			g_srCurrentServer.bShowInServerList,
			g_srCurrentServer.iMaxPlayers,
			g_srCurrentServer.iReservedSlots,
			g_srCurrentServer.bHiddenSlots,
			g_srCurrentServer.bIncludeBots,
			g_srCurrentServer.sServerMap,
			g_iServerTimeOut,
			g_srCurrentServer.iServerID
			);
		}
	}
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Update Query: %s", Query);
	
	DB.Query(T_FakeFastQuery, Query, _, dbPriority);
}

// Registering a new server in the Database server.
stock void RegisterServer()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- RegisterServer");
	
	DB.Format(Query, sizeof(Query), "INSERT INTO `server_redirect_servers`(`server_id`, `server_name`, `server_category`, `server_ip`, `server_port`, `server_status`, `server_map`, `number_of_players`, `max_players`, `reserved_slots`, `hidden_slots`, `server_visible`, `timeout_time`) VALUES (%d, '%s', '%s', %d, %d, %d, '%s', %d, %d, %d, %d, %b, %d)", 
		g_srCurrentServer.iServerID, 
		g_srCurrentServer.sServerName, 
		g_srCurrentServer.sServerCategory, 
		g_srCurrentServer.iServerIP32, 
		g_srCurrentServer.iServerPort, 
		g_srCurrentServer.bServerStatus, 
		g_srCurrentServer.sServerMap, 
		g_srCurrentServer.iNumOfPlayers, 
		g_srCurrentServer.iMaxPlayers,
		g_srCurrentServer.iReservedSlots,
		g_srCurrentServer.bHiddenSlots,
		g_srCurrentServer.bShowInServerList,
		g_iServerTimeOut
		);
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Register Query: %s", Query);
	
	DB.Query(T_FakeFastQuery, Query, _, DBPrio_High);
}

// Updating the server info in the Database server.
stock void UpdateServerInfo()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- UpdateServerInfo");
		
	Format(Query, sizeof(Query), "SELECT * FROM `server_redirect_servers` WHERE `server_id` = %d", g_srCurrentServer.iServerID);
	DB.Query(T_OnServerSearchReceived, Query, _, DBPrio_High);
}

stock void CheckIfServerTimedOut(int iServerID)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- CheckIfServerTimedOut");
	
	Format(Query, sizeof(Query), "SELECT UNIX_TIMESTAMP(`unix_lastupdate`), `timeout_time` * 60  FROM `server_redirect_servers` WHERE `server_id` = %d", iServerID);
	DB.Query(T_OnTimeoutResultReceived, Query, iServerID, DBPrio_Low);
}

void T_OnTimeoutResultReceived(Handle owner, Handle hQuery, const char[] sError, any iServerID)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnTimeoutResultReceived");
		
	if (hQuery != INVALID_HANDLE)
	{
		// If the server exists:
		if(SQL_FetchRow(hQuery))
		{
			int iTimeWithoutUpdate = GetTime() - SQL_FetchInt(hQuery, 0);
			
			if(iTimeWithoutUpdate >= SQL_FetchInt(hQuery, 1))
			{
				if (g_cvPrintDebug.BoolValue)
					LogMessage("Deleting Server (Server-ID - %d | Last update - %d | timeout time in sec - %d | time without update %d)",
					iServerID,
					SQL_FetchInt(hQuery, 0),
					SQL_FetchInt(hQuery, 1),
					GetTime() - SQL_FetchInt(hQuery, 0)
					);
				
				Format(Query, sizeof(Query), "DELETE FROM `server_redirect_servers` WHERE `server_id` = %d", iServerID);
				DB.Query(T_FakeFastQuery, Query, _, DBPrio_Low);
				
				Server CleanServer;
				g_srOtherServers[iServerID] = CleanServer;
			}
		}
		else
			LogError("%s Somehow we didn't find the server?", PREFIX_NO_COLOR);
	}
	else // We got an error while trying to send this query, don't continue.
		SetFailState("%s Error in T_OnInfoNameReceived: %s", PREFIX_NO_COLOR, sError);
}

void T_OnServerSearchReceived(Handle owner, Handle hQuery, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnServerSearchReceived");
	
	if (hQuery != INVALID_HANDLE)
	{
		// If the server exists:
		if(SQL_FetchRow(hQuery))
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Found Server: ID - %d", g_srCurrentServer.iServerID);
			
			// Update the server.
			UpdateServer(UPDATE_SERVER_START, DBPrio_Normal);
		}
		else // else, the server doesn't exit:
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Didn't find any servers with the ID - %d, Registering it.", g_srCurrentServer.iServerID);
			
			// Register it.
			RegisterServer();
		}
	}
	else // We got an error while trying to send this query, don't continue.
		SetFailState("%s Error in T_OnInfoNameReceived: %s", PREFIX_NO_COLOR, sError);
}

void T_FakeFastQuery(Handle owner, Handle hQuery, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_FakeFastQuery");
	
	if (hQuery == INVALID_HANDLE)
		LogError("Error in T_FakeFastQuery: %s", sError);
}

//==================================[ HELPING ]==============================//
// Checking if the sent client is valid based of the parmeters sent and other other functions.
stock bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || IsClientSourceTV(client) || IsClientReplay(client) || (IsFakeClient(client) && !bAllowBots) || (!bAllowDead && !IsPlayerAlive(client)))
		return false;
	return true;
}

// Load Server Settings
stock void LoadSettings()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadServerListCommands");
	
	KeyValues kvSettings = CreateKeyValues("ServerRedirectSettings");
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), SETTINGS_PATH);
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if(!kvSettings.ImportFromFile(sPath) || !kvSettings.JumpToKey("Settings"))
		SetFailState("%s Couldn't load plugin config.", PREFIX_NO_COLOR);
	
	// Get the ServerID
	g_srCurrentServer.iServerID = kvSettings.GetNum("ServerID", -1);
	
	// If the ServerID is invalid don't continue.
	if(g_srCurrentServer.iServerID < 0)
		SetFailState("%s Invalid Server-ID, please change / add a vaild value (0 or Higher) on 'ServerID' in the plugin config.", PREFIX_NO_COLOR);
	
	// Get the rest of the settings if everything is ok
	g_srCurrentServer.bIncludeBots 		= view_as<bool>(kvSettings.GetNum("ShowBots"				, 0));
	g_srCurrentServer.bShowInServerList = view_as<bool>(kvSettings.GetNum("ShowSeverInServerList"	, 1));
	
	g_bEnableAdvertisements 	= view_as<bool>(kvSettings.GetNum("EnableAdvertisements"	, 1));
	g_bAdvertiseOfflineServers 	= view_as<bool>(kvSettings.GetNum("AdvertiseOfflineServers"	, 0));
	
	g_iServerTimeOut = kvSettings.GetNum("ServerTimeOut", 1440);
	
	kvSettings.GetString("MenuFormat"			, g_sMenuFormat						, sizeof(g_sMenuFormat)						);
	kvSettings.GetString("PrefixRemover"		, g_sPrefixRemover					, sizeof(g_sPrefixRemover)					);
	kvSettings.GetString("ServerListCommands"	, g_sServerListCommands				, sizeof(g_sServerListCommands)				);
	kvSettings.GetString("ServerName"			, g_srCurrentServer.sServerName		, sizeof(g_srCurrentServer.sServerName)		);
	kvSettings.GetString("ServerCategory"		, g_srCurrentServer.sServerCategory	, sizeof(g_srCurrentServer.sServerCategory)	);
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Settings Loaded:\n • MenuFormat: %s\n • ServerListCommands: %s\n • ServerName: %s\n • ServerCategory: %s\n • ShowBots: %d\n • ShowSeverInServerList: %d",
		g_sMenuFormat,
		g_sServerListCommands,
		g_srCurrentServer.sServerName,
		g_srCurrentServer.sServerCategory,
		g_srCurrentServer.bIncludeBots,
		g_bShowServerOnServerList
		);
}

// Load the commands for the Server-List
stock void LoadServerListCommands()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadServerListCommands");
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Commands: %s", g_sServerListCommands);
	
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

// Starting the server update timer if it's not already running.
stock void StartUpdateTimer()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- StartUpdateTimer");
	
	if (g_hServerUpdateTimer == INVALID_HANDLE)
	{
		g_hServerUpdateTimer = CreateTimer(g_cvUpdateServerInterval.FloatValue, Timer_UpdateServerInDatabase);
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("ServerUpdateTimer Started");
	}
	else if (g_cvPrintDebug.BoolValue)
		LogMessage("ServerUpdateTimer didn't start because it's already running (Valid: %b)", g_hServerUpdateTimer != INVALID_HANDLE);
}

// Get the name of the workshop map.
stock void GetCurrentWorkshopMap(char[] sMap, int iMapBuf)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- GetCurrentWorkshopMap");
	
	char sCurMap[128];
	char sMapSplit[2][64];
	
	GetCurrentMap(sCurMap, sizeof(sCurMap));
	ReplaceString(sCurMap, sizeof(sCurMap), "workshop/", "", false);
	ExplodeString(sCurMap, "/", sMapSplit, 2, 64);
	
	strcopy(sMap, iMapBuf, sMapSplit[1]);
}

// Getting the number of players that aren't bots.
stock int GetClientCountEx(bool bIncludeBots)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage("<-- GetClientCountEx | bIncludeBots - %d", bIncludeBots);
	
	int iClientCount = 0;
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	if (IsValidClient(iCurrentClient, bIncludeBots, true))
		iClientCount++;
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("%d real clients are in the server. (with%s bots)", iClientCount, bIncludeBots ? "" : "out");
	
	return iClientCount;
}

// Copying a string to it's destination and adding a '...' if the string isn't fully shown.
stock int CopyStringWithDots(char[] sDest, int iDestLen, char[] sSource, int iSourceLen)
{
	strcopy(sDest, iDestLen, sSource);
	if(strlen(sSource) > iDestLen && iDestLen > 3)
		strcopy(sDest[iDestLen - 4], iDestLen, "...");
	
	return iDestLen - strlen(sSource);
}

// Getting the Server-IP32
stock int GetServerIP32()
{
	// Gets the server public IP
	int sIPFull[4];
	SteamWorks_GetPublicIP(sIPFull);
	
	// Save the IP32
	int iFullIP32 = sIPFull[0] << 24 | sIPFull[1] << 16 | sIPFull[2] << 8 | sIPFull[3];
	
	// If the IP32 is 0 we need to get it in another way. If it's still 0 just return it :/
	return iFullIP32 == 0 ? FindConVar("hostip").IntValue : iFullIP32;
}

// Getting the server info and storing it.
stock void GetServerInfo()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- GetServerInfo");
	
	// If it's blank, grab the server hostname
	if (StrEqual(g_srCurrentServer.sServerName, "", false))
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Server name was empty. Getting the hostname.");
		
		GetConVarString(FindConVar("hostname"), g_srCurrentServer.sServerName, sizeof(g_srCurrentServer.sServerName));
	}
	
	// Get server map
	GetCurrentMap(g_srCurrentServer.sServerMap, sizeof(g_srCurrentServer.sServerMap));
	
	// Get only the name of the map if it's a workshop map
	if (StrContains(g_srCurrentServer.sServerMap, "workshop/", false) != -1)
		GetCurrentWorkshopMap(g_srCurrentServer.sServerMap, sizeof(g_srCurrentServer.sServerMap));
	
	// After everything we couldn't get the IP32, so we have no point to continue
	if((g_srCurrentServer.iServerIP32 = GetServerIP32()) == 0)
		SetFailState("%s Couldn't get the server IP", PREFIX_NO_COLOR);
	
	// Get the server Max-Players
	g_srCurrentServer.iMaxPlayers = GetMaxHumanPlayers();
	
	// If reserved slots is used, lets take it to count.
	if(g_cvReservedSlots)
		g_srCurrentServer.iReservedSlots = g_cvReservedSlots.IntValue;
	
	if(g_cvHiddenSlots)
		g_srCurrentServer.bHiddenSlots = g_cvHiddenSlots.BoolValue;
	
	// Get the server Port
	g_srCurrentServer.iServerPort = GetConVarInt(FindConVar("hostport"));
	
	// Get the server Player-Count
	g_srCurrentServer.iNumOfPlayers = GetClientCountEx(g_srCurrentServer.bIncludeBots);
	
	// Set the server status to online.
	g_srCurrentServer.bServerStatus = true;
	
	if (g_cvPrintDebug.BoolValue)
	{
		char iIP[4][4];
		GetIPv4FromIP32(g_srCurrentServer.iServerIP32, iIP);
		LogMessage("Name - %s\nCategory - %s\nIP32 - %d\nIP - %s.%s.%s.%s\nPort - %d\nMap - %s\nNumber of players - %d\nMax Players - %d\nshow server - %b", 
			g_srCurrentServer.sServerName,
			g_srCurrentServer.sServerCategory,
			g_srCurrentServer.iServerIP32,
			iIP[0], iIP[1], iIP[2], iIP[3],
			g_srCurrentServer.iServerPort,
			g_srCurrentServer.sServerMap,
			g_srCurrentServer.iNumOfPlayers,
			g_srCurrentServer.iMaxPlayers,
			g_srCurrentServer.bShowInServerList
			);
	}
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
stock bool String_StartsWith(const char[] str, const char[] subString)
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

/**
 * Checks if string str ends with subString.
 * 
 *
 * @param str				String to check
 * @param subString			Sub-String to check in str
 * @return					True if str ends with subString, false otherwise.
 */
stock bool String_EndsWith(const char[] str, const char[] subString)
{
	int n_str = strlen(str) - 1;
	int n_subString = strlen(subString) - 1;

	if(n_str < n_subString)
		return false;

	while (n_str != 0 && n_subString != 0)
		if (str[n_str--] != subString[n_subString--])
			return false;

	return true;
}

/* TODO:
* This Release:
* 1. [✓] Add an option to delete a sever from the database. (insted add a "time-out" so servers that didn't got updated in x min will get deleted) 
* 2. [✗] Add an option to show / hide certian servers.
* 3. [✓] Add reserve slot support for the player-count. FIX?[✓]
*
* Later Releases:
* 1. [✗] Make the plugin more dynamic and use arraylist so i wont have to use fixed arrays
* 2. [✗] Party mod :P
*
* • FINALLY FUCKING PUBLISH IT TO THE PUBLIC VERSION (hope i will remember deleting this before publishing; i wrote this in 2AM)
*/

/* What was added?
* 1. Advertisements! (formatable messages, Map-Change message, Player-Range message, do / don't Advertise offline servers)
* 2. Auto Time-Out server deletion.
* 3. Config instead of the old ConVars
* 4. Control over Commands that open the Server-List.
* 5. Prefix Remover
* 6. ERROR FIX for the map start invalid database handle (and maybe crashes?)
* 7. File is now lighter, removed the 'smlib' include and took only 2 things i needed
* 8. Added reserve slot support, override command 'server_redirect_use_reserved_slots' or ROOT admin-flag can see reserved slots.
* 9. FIX ServerList menu glitching out and not showing part of the servers / next / back buttons.
*
*
*/