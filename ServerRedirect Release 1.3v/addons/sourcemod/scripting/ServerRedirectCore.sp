#include <sourcemod>
#include <steamworks>
#include <smlib>
#include <redirect_core>
#include <multicolors>

#pragma newdecls required
#pragma semicolon 1

#define PREFIX " \x04[Server-Redirect+]\x01"
#define PREFIX_NO_COLOR "[Server-Redirect+]"

#define SETTINGS_PATH "configs/ServerRedirect/Config.cfg"

#define MAX_SERVER_LIST_COMMANDS 15
#define MAX_SERVER_NAME_LENGHT 30
#define MAX_CATEGORY_LENGHT 32
#define MAX_MAP_NAME_LENGHT 15
#define MAX_SERVERS 50
#define MAX_BUFFER_SIZE 80
#define MAX_ADVERTISEMENTS MAX_SERVERS * 4

//============[ DB ]============//
Database DB = null;
char Query[512];

//=======[ Update Timer ]=======//
Handle g_hServerUpdateTimer = INVALID_HANDLE; 	// Update this server
Handle g_hOtherServersUpdateTimer;				// Update other servers
int g_iTimerCounter;							// Timer For Advertisements

//==========[ Settings ]=========//
ConVar 	g_cvUpdateOtherServersInterval; 		// Timer Interval for other servers update
ConVar 	g_cvUpdateServerInterval; 				// Time between each update
ConVar 	g_cvPrintDebug; 						// Debug Mode Status

bool 	g_bIncludeBotsInPlayerCount;			// Include bots in the player-count?
bool 	g_bShowServerOnServerList; 				// Show this server in the Server-List?
bool 	g_bEnableAdvertisements; 				// Should we advertise servers?
bool 	g_bAdvertiseOfflineServers; 			// Should we advertise offline servers?

char 	g_sServerListCommands[256];				// Commands for the Server-List.
char 	g_sMenuFormat[128]; 					// Menu Server Format
char 	g_sRemoveString[128]; 					// String to remove from the server name (useful for removing prefixs)

//=====[ ADVERTISEMENT ENUM ]===//
enum
{
	ADVERTISEMENT_LOOP		 	=  0, // USING TIMER
	ADVERTISEMENT_MAP 		 	= -1, // USING DEFFRENCE CHECK
	ADVERTISEMENT_PLAYERS_RANGE = -2  // USING DEFFRENCE CHECK
}

enum struct Advertisement
{
	int iAdvID;					// Advertisement ID
	int iServerIDToAdvertise;	// Advertised Server
	int iRepeatTime;			// How long to wait between each advertise
	int iCoolDownTime;			// How long should this advertisement should be on cooldown (for 'deffrence check' advertisements)
	int iAdvertisedTime;		// Used for calculating if the advertisement should post
	int iPlayersRange[2]; 		// 0 - MIN | 1 - MAX
	
	char sMessageContent[512];	// Message to print
}
Advertisement g_advAdvertisements[MAX_ADVERTISEMENTS];

Advertisement g_advToEdit;

enum
{
	UPDATE_NOTHING 			= -1,
	UPDATE_LOOP_TIME 		=  0,
	UPDATE_COOLDOWN_TIME 	=  1,
	UPDATE_PLAYER_RANGE 	=  2,
	UPDATE_ADV_MESSAGE 		=  3
}
int g_iUpdateAdvProprietary[MAXPLAYERS + 1] =  { UPDATE_NOTHING, ... };

//=======[ SERVER STRUCT ]======//
enum struct Server
{
	char sServerCategory[MAX_CATEGORY_LENGHT];
	char sServerName[MAX_SERVER_NAME_LENGHT];
	char sServerMap[MAX_MAP_NAME_LENGHT];
	
	int iNumOfPlayers;
	int iServerIP32;
	int iServerPort;
	int iMaxPlayers;
	int iServerID;
	
	bool bShowInServerList;
	bool bServerFoundInDB;
	bool bServerStatus;
	bool bIncludeBots;
}
Server g_srCurrentServer;
Server g_srOtherServers[MAX_SERVERS];

//========[ UPDATE ENUM ]=======//
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
	description = "Core of 'Server-Redirect+', gathering information about the server and sending it to the SQL.", 
	version = "1.3", 
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
	
	//==============================[ HOOKS ]===========================//
	HookEvent("server_shutdown", Event_ServerShutDown, EventHookMode_Pre);
	
	//==========================[ ADMIN COMMANDS ]======================//
	RegAdminCmd("sm_editsradv", Command_EditServerRedirectAdvertisements, ADMFLAG_ROOT, "Edit server Advertisements");
	
	//==========================[ Console-Vars ]========================//
	g_cvUpdateOtherServersInterval 	= CreateConVar("server_redirect_other_servers_update_interval"	, "20.0", "The number of seconds between other servers update."											, _, true, 5.0, true, 600.0	);
	g_cvUpdateServerInterval 		= CreateConVar("server_redirect_server_update_interval"			, "20.0", "The number of seconds the plugin will wait before updating player count in the SQL server." 	, _, true, 0.0, true, 600.0	);
	g_cvPrintDebug 					= CreateConVar("server_redirect_debug_mode"						, "0"	, "Whether or not to print debug messages in server console"									, _, true, 0.0, true, 1.0	);
	
	//========================[ CVAR Change Hooks ]=====================//
	g_cvUpdateOtherServersInterval.AddChangeHook(OnCvarChange);
	
	//=========================[ AutoExec Config ]======================//
	AutoExecConfig(true);
	
	//========================[ Load Translations ]=====================//
	LoadTranslations("server_redirect.phrases");
	
	// Load Settings from the config
	if(!LoadSettings())
		SetFailState("%s Couldn't load plugin config.", PREFIX_NO_COLOR);
	
	// Load the Server-List commands from the convar / config
	LoadServerListCommands();
	
	// Get Server info to send to the database
	GetServerInfo();
}

public void OnConfigsExecuted()
{
	// Loading the Database
	LoadDB();
}

// OnClientConnected & OnClientDisconnect_Post Will start the Server-Update timer if it's not already running.
public void OnClientPostAdminCheck(int client)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnClientConnected | int client =  %d", client);
	
	// If the user doesn't want bots, don't enter here.
	if (!IsFakeClient(client) || g_bIncludeBotsInPlayerCount)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("%N is valid (bots: %b)", client, g_bIncludeBotsInPlayerCount);
		
		// Starting the update timer.
		StartUpdateTimer();
		
		if (g_cvPrintDebug.BoolValue)
			LogMessage("Client connected, starting timer");
		
	}
	else if (g_cvPrintDebug.BoolValue)
		LogMessage("%N isn't valid (bots: %b)", client, g_bIncludeBotsInPlayerCount);
}

// OnClientConnected & OnClientDisconnect Will start the Server-Update timer if it's not already running.
public void OnClientDisconnect(int client)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnClientDisconnect | int client =  %d", client);
	
	// If the user doesn't want bots, don't enter here.
	if (!IsFakeClient(client) || g_bIncludeBotsInPlayerCount)
	{
		// Get the client count
		g_srCurrentServer.iNumOfPlayers = GetClientCountEx(g_bIncludeBotsInPlayerCount);
		
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
	
	KillTimer(g_hOtherServersUpdateTimer);
	g_hOtherServersUpdateTimer = CreateTimer(StringToFloat(newValue), Timer_UpdateOtherServers, _, TIMER_REPEAT);
}

// Updating the Server-Status in the SQL server before shut-down.
public Action Event_ServerShutDown(Event event, const char[] name, bool dontBroadcast)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Event_ServerShutDown");
	
	OnPluginEnd();
	
	g_srCurrentServer.bServerStatus = false;
	UpdateServer(UPDATE_SERVER_STATUS);
}

// Updating the Server-Status in the SQL server before plugin unload.
public void OnPluginEnd()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- OnPluginEnd");
	
	// If the plugin is getting unloaded, probably the server is off so we want to update the server status in the database.
	if (!g_srCurrentServer.bServerStatus)
	{
		g_srCurrentServer.bServerStatus = false;
		UpdateServer(UPDATE_SERVER_STATUS);
	}
}

//==================================[ TIMERS ]==============================//
// After the Update-Interval time has passed, updae the server.
public Action Timer_UpdateServerInDatabase(Handle timer)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Timer_UpdateServerInDatabase");
	
	// Get Client-Count
	g_srCurrentServer.iNumOfPlayers = GetClientCountEx(g_bIncludeBotsInPlayerCount);
	
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
		LogMessage(" <-- LoadDB");
	
	// Connect to the database
	Database.Connect(T_OnDBConnected, "ServerRedirect", bOnlyConnect);
}

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
		
		DB.Query(T_OnDatabaseReady, "CREATE TABLE IF NOT EXISTS server_redirect_servers (`id` INT NOT NULL AUTO_INCREMENT,`server_id` INT NOT NULL, `server_name` TEXT NOT NULL, `server_category` TEXT NOT NULL, `server_ip` TEXT NOT NULL, `server_port` INT NOT NULL, `server_status` INT NOT NULL, `server_visible` INT NOT NULL, `server_map` TEXT NOT NULL, `number_of_players` INT NOT NULL, `max_players` INT NOT NULL, PRIMARY KEY (`id`), UNIQUE(`server_id`))", _, DBPrio_High);
		CreateAdvertisementsTable();
	}
}

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
			DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `number_of_players` = %d WHERE `server_id` = %d", g_srCurrentServer.iNumOfPlayers, g_srCurrentServer.iServerID);
		case UPDATE_SERVER_STATUS:
			DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `server_status` = %d WHERE `server_id` = %d", g_srCurrentServer.bServerStatus, g_srCurrentServer.iServerID);
		case UPDATE_SERVER_START:
			DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_servers` SET `server_name` = '%s', `server_ip` = %d, `server_port` = %d, `server_status` = %d, `server_visible` = %d, `max_players` = %d, `server_map` = '%s' WHERE `server_id` = %d", g_srCurrentServer.sServerName, g_srCurrentServer.iServerIP32, g_srCurrentServer.iServerPort, g_srCurrentServer.bServerStatus, g_srCurrentServer.bShowInServerList, g_srCurrentServer.iMaxPlayers, g_srCurrentServer.sServerMap, g_srCurrentServer.iServerID);
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
	
	DB.Format(Query, sizeof(Query), "INSERT INTO `server_redirect_servers`(`server_id`, `server_name`, `server_category`, `server_ip`, `server_port`, `server_status`, `server_map`, `number_of_players`, `max_players`, `server_visible`) VALUES (%d, '%s', '%s', %d, %d, %d, '%s', %d, %d, %d)", 
		g_srCurrentServer.iServerID, 
		g_srCurrentServer.sServerName, 
		g_srCurrentServer.sServerCategory, 
		g_srCurrentServer.iServerIP32, 
		g_srCurrentServer.iServerPort, 
		g_srCurrentServer.bServerStatus, 
		g_srCurrentServer.sServerMap, 
		g_srCurrentServer.iNumOfPlayers, 
		g_srCurrentServer.iMaxPlayers, 
		g_srCurrentServer.bShowInServerList
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
		
	DB.Format(Query, sizeof(Query), "SELECT * FROM `server_redirect_servers` WHERE `server_id` = %d", g_srCurrentServer.iServerID);
	DB.Query(T_OnServerSearchReceived, Query, _, DBPrio_High);
}

public void T_OnServerSearchReceived(Handle owner, Handle hQuery, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnServerSearchReceived");
	
	if (hQuery != INVALID_HANDLE)
	{
		if(SQL_FetchRow(hQuery))
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Found Server: ID - %d", g_srCurrentServer.iServerID);
			
			g_srCurrentServer.bServerFoundInDB = true;
		
			UpdateServer(UPDATE_SERVER_START, DBPrio_Normal);
		}
		else
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Didn't find any servers with the ID - %d, Registering it.", g_srCurrentServer.iServerID);
			
			RegisterServer();
		}
	}
	else
		SetFailState("%s Error in T_OnInfoNameReceived: %s", PREFIX_NO_COLOR, sError);
}

public void T_FakeFastQuery(Handle owner, Handle hQuery, const char[] sError, any data)
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
stock bool LoadSettings()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadServerListCommands");
	
	KeyValues kvSettings = CreateKeyValues("ServerRedirectSettings");
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), SETTINGS_PATH);
	
	if(!kvSettings.ImportFromFile(sPath) || !kvSettings.JumpToKey("Settings"))
		return false;
	
	//kvSettings.GotoFirstSubKey(false);
	
	g_srCurrentServer.iServerID = kvSettings.GetNum("ServerID", -1);
	
	if(g_srCurrentServer.iServerID == -1)
		SetFailState("%s Invalid Server-ID, please change / add a vaild value (0 or Higher) on 'ServerID' in the plugin config.", PREFIX_NO_COLOR);
	
	g_srCurrentServer.bIncludeBots 		= view_as<bool>(kvSettings.GetNum("ShowBots"				, 0));
	g_srCurrentServer.bShowInServerList = view_as<bool>(kvSettings.GetNum("ShowSeverInServerList"	, 1));
	
	g_bEnableAdvertisements 	= view_as<bool>(kvSettings.GetNum("EnableAdvertisements"	, 1));
	g_bAdvertiseOfflineServers 	= view_as<bool>(kvSettings.GetNum("AdvertiseOfflineServers"	, 0));
	
	kvSettings.GetString("MenuFormat"			, g_sMenuFormat						, sizeof(g_sMenuFormat)						);
	kvSettings.GetString("PrefixRemover"		, g_sRemoveString					, sizeof(g_sRemoveString)					);
	kvSettings.GetString("ServerListCommands"	, g_sServerListCommands				, sizeof(g_sServerListCommands)				);
	kvSettings.GetString("ServerName"			, g_srCurrentServer.sServerName		, sizeof(g_srCurrentServer.sServerName)		);
	kvSettings.GetString("ServerCategory"		, g_srCurrentServer.sServerCategory	, sizeof(g_srCurrentServer.sServerCategory)	);
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Settings Loaded:\n • MenuFormat: %s\n • ServerListCommands: %s\n • ServerName: %s\n • ServerCategory: %s\n • ShowBots: %d\n • ShowSeverInServerList: %d",
		g_sMenuFormat,
		g_sServerListCommands,
		g_srCurrentServer.sServerName,
		g_srCurrentServer.sServerCategory,
		g_bIncludeBotsInPlayerCount,
		g_bShowServerOnServerList
		);
	
	return true;
}

// Load the commands for the Server-List
stock void LoadServerListCommands()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadServerListCommands");
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Commands: %s", g_sServerListCommands);
	
	char sSingleCommands[MAX_SERVER_LIST_COMMANDS][16];
	ExplodeString(g_sServerListCommands, ",", sSingleCommands, MAX_SERVER_LIST_COMMANDS, sizeof(sSingleCommands[]));
	
	for (int iCurrentCommand = 0; iCurrentCommand < MAX_SERVER_LIST_COMMANDS; iCurrentCommand++)
	{
		if(!StrEqual(sSingleCommands[iCurrentCommand], "", false))
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("sSingleCommands[%d]: %s", iCurrentCommand, sSingleCommands[iCurrentCommand]);
			
			RegConsoleCmd(sSingleCommands[iCurrentCommand], Command_ServerList, "Opens the Server-List Menu.");
		}
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
stock int GetClientCountEx(bool includeBots)
{
	int iClientCount = 0;
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	if (IsValidClient(iCurrentClient, includeBots, true))
		iClientCount++;
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("%d real clients are in the server.", iClientCount);
	
	return iClientCount;
}

// Getting the server info and storing it.
stock void GetServerInfo()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- GetServerInfo");
	
	// If it's blank, grab the server hostname
	if (StrEqual(g_srCurrentServer.sServerName, "", false))
	{
		char sServerNameFull[128];
		Server_GetHostName(sServerNameFull, sizeof(sServerNameFull));
		
		// Remove the Prefix string
		if(!StrEqual(g_sRemoveString, "", false))
			ReplaceString(sServerNameFull, sizeof(sServerNameFull), g_sRemoveString, "", true);
		
		// Save the Prefix-less name.
		strcopy(g_srCurrentServer.sServerName, sizeof(g_srCurrentServer.sServerName), sServerNameFull);
	}
	
	// Get server map
	GetCurrentMap(g_srCurrentServer.sServerMap, sizeof(g_srCurrentServer.sServerMap));
	
	// Get only the name of the map if it's a workshop map
	if (StrContains(g_srCurrentServer.sServerMap, "workshop/", false) != -1)
		GetCurrentWorkshopMap(g_srCurrentServer.sServerMap, sizeof(g_srCurrentServer.sServerMap));
	
	// Gets the server public IP
	int sIPFull[4];
	char sIPv4[4][4];
	SteamWorks_GetPublicIP(sIPFull);
	IntToString(sIPFull[0], sIPv4[0], sizeof(sIPv4));
	IntToString(sIPFull[1], sIPv4[1], sizeof(sIPv4));
	IntToString(sIPFull[2], sIPv4[2], sizeof(sIPv4));
	IntToString(sIPFull[3], sIPv4[3], sizeof(sIPv4));
		
	g_srCurrentServer.iServerIP32 = GetIP32FromIPv4(sIPv4);
	
	// Get the server Max-Players
	g_srCurrentServer.iMaxPlayers = GetMaxHumanPlayers();
	
	// Get the server Port
	g_srCurrentServer.iServerPort = Server_GetPort();
	
	// Get the server Player-Count
	g_srCurrentServer.iNumOfPlayers = GetClientCountEx(g_bIncludeBotsInPlayerCount);
	
	// Get the server 
	g_srCurrentServer.bServerStatus = true;
	g_srCurrentServer.bServerFoundInDB = false;
	
	if (g_cvPrintDebug.BoolValue)
	{
		char iIP[4][4];
		GetIPv4FromIP32(g_srCurrentServer.iServerIP32, iIP);
		LogMessage("Name - %s, Category - %s, IP32 - %d, IP - %s.%s.%s.%s, Port - %d, Map - %s, Number of players - %d, show server - %b", 
			g_srCurrentServer.sServerName, 
			g_srCurrentServer.sServerCategory, 
			g_srCurrentServer.iServerIP32, 
			iIP[0], iIP[1], iIP[2], iIP[3], 
			g_srCurrentServer.iServerPort, 
			g_srCurrentServer.sServerMap, 
			g_srCurrentServer.iNumOfPlayers, 
			g_srCurrentServer.bShowInServerList
			);
	}
}