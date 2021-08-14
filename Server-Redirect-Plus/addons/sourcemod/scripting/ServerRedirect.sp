#include <sourcemod>
#include <dhooks>

#include "serverRedirect/redirect/net.sp"
#include "serverRedirect/redirect/redirect.sp"

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
	name = "[Core] Server-Redirect",
	author = "Natanel 'LuqS'",
	description = "",
	version = "1.0.0",
	url = "https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_CSGO)
	{
		strcopy(error, err_max, "This plugin is for CS:GO only.");
		return APLRes_Failure; 
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	// Setup and initialize all of the stuff to redirect players between servers.
	SetupRedirectSDK();

	// Register all commands.
	RegisterCommands();
}


void SetupRedirectSDK()
{
	// client ip → redirect ip.
	g_ShouldReconnect = new StringMap();

	// GameData that contains signatures and offsets.
	GameData gamedata = new GameData("server_redirect.games");
	
	// Setup everything for the redirection feature.
	SetupNet(gamedata);
	SetupSDKCalls(gamedata);
	SetupDhooks(gamedata);
}