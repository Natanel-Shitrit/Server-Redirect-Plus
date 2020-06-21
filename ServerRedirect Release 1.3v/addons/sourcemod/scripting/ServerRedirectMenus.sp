public Plugin myinfo = 
{
	name = "[Server-Redirect+] Menus",
	author = "Natanel 'LuqS'",
	description = "Menus of 'Server-Redirect+', getting all other servers information and displaying it in the menu.",
	version = "1.0",
	url = "https://steamcommunity.com/id/luqsgood | Discord: LuqS#6505"
};

// SQL Callback for LoadServers()
public void T_OnServersReceive(Handle owner, Handle hQuery, const char[] sError, any data)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnServersReceive");
	
	if(hQuery != INVALID_HANDLE)
	{
		int iCurrentServer;
		
		for (iCurrentServer = 0; iCurrentServer < MAX_SERVERS && SQL_FetchRow(hQuery); iCurrentServer++) 
		{
			g_srOtherServers[iCurrentServer].bServerFoundInDB 	= true;
			g_srOtherServers[iCurrentServer].iServerID	 		= SQL_FetchIntByName(hQuery, "server_id");
			g_srOtherServers[iCurrentServer].bServerStatus 		= SQL_FetchBoolByName(hQuery, "server_status");
			g_srOtherServers[iCurrentServer].bShowInServerList 	= SQL_FetchBoolByName(hQuery, "server_visible");
			
			if(g_cvPrintDebug.BoolValue)
				LogMessage("[T_OnServersReceive -> LOOP] Server %d: Status %b, Show: %b", iCurrentServer, g_srOtherServers[iCurrentServer].bServerStatus, g_srOtherServers[iCurrentServer].bShowInServerList);
			
			if(g_srOtherServers[iCurrentServer].bServerStatus)
			{
				SQL_FetchStringByName(hQuery, "server_name"		, g_srOtherServers[iCurrentServer].sServerName		, sizeof(g_srOtherServers[].sServerName		));
				SQL_FetchStringByName(hQuery, "server_category"	, g_srOtherServers[iCurrentServer].sServerCategory	, sizeof(g_srOtherServers[].sServerCategory	));
				
				char sOldMap[MAX_MAP_NAME_LENGHT];
				if(!StrEqual(g_srOtherServers[iCurrentServer].sServerMap, "", false))
					strcopy(sOldMap, sizeof(sOldMap), g_srOtherServers[iCurrentServer].sServerMap);
					
				SQL_FetchStringByName(hQuery, "server_map"		, g_srOtherServers[iCurrentServer].sServerMap		, sizeof(g_srOtherServers[].sServerMap		));
				
				if(!StrEqual(sOldMap, g_srOtherServers[iCurrentServer].sServerMap))
					PostAdvertisement(g_srOtherServers[iCurrentServer].iServerID, ADVERTISEMENT_MAP);
				
				int iServerAdvertisement = FindAdvertisement(g_srOtherServers[iCurrentServer].iServerID, ADVERTISEMENT_PLAYERS_RANGE);
				
				if(iServerAdvertisement != -1)
					if(g_advAdvertisements[iServerAdvertisement].iPlayersRange[0] < g_srOtherServers[iCurrentServer].iNumOfPlayers < g_advAdvertisements[iServerAdvertisement].iPlayersRange[1])
						PostAdvertisement(g_srOtherServers[iCurrentServer].iServerID, ADVERTISEMENT_PLAYERS_RANGE);
						
				g_srOtherServers[iCurrentServer].iServerIP32 	= SQL_FetchIntByName(hQuery, "server_ip"			);
				g_srOtherServers[iCurrentServer].iServerPort 	= SQL_FetchIntByName(hQuery, "server_port"			);
				g_srOtherServers[iCurrentServer].iNumOfPlayers 	= SQL_FetchIntByName(hQuery, "number_of_players"	);
				g_srOtherServers[iCurrentServer].iMaxPlayers 	= SQL_FetchIntByName(hQuery, "max_players"			);
				
				
				
				if(g_cvPrintDebug.BoolValue)
					LogMessage("[T_OnServersReceive -> LOOP -> IF] Name: %s, Category: %s, Map: %s, IP32: %d, Port: %d, Number of players: %d, Max players: %d",
					g_srOtherServers[iCurrentServer].sServerName,
					g_srOtherServers[iCurrentServer].sServerCategory,
					g_srOtherServers[iCurrentServer].sServerMap,
					g_srOtherServers[iCurrentServer].iServerIP32,
					g_srOtherServers[iCurrentServer].iServerPort,
					g_srOtherServers[iCurrentServer].iNumOfPlayers,
					g_srOtherServers[iCurrentServer].iMaxPlayers
					);
			}
		}
		CleanServersArray(iCurrentServer);
		
		if(!iCurrentServer)
			LogError("No servers found in DB.");
		
		if(SQL_FetchRow(hQuery))
			LogError("%s There is more servers in SQL-Database server than MAX_SERVERS, please recompile it with MAX_SERVERS with greater amount.", PREFIX_NO_COLOR);
	}
	else
		LogError("Error: %s", sError);
}

// Timer for other servers update
public Action Timer_UpdateOtherServers(Handle timer)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Timer_UpdateOtherServers");
	
	if(GetClientCountEx(false) != 0 && DB != null)
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage("[Timer_UpdateOtherServers -> IF] Loading Servers");
		
		LoadServers();
	}
	else if(g_cvPrintDebug.BoolValue)
		LogMessage("[Timer_UpdateOtherServers -> ELSE] Not loading servers because server is empty.");
		
	return Plugin_Continue;
}

//==================================[ MENUS & HANDLES ]==============================//
public Action Command_ServerList(int client, int args)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Command_ServerList | Fired by %N (%d)", client, client);
	
	Menu mServerList = new Menu(ServerListMenuHandler);
	mServerList.SetTitle("%t", "MenuTitleMain", PREFIX_NO_COLOR);
	
	mServerList.AddItem("EditAdvertisements", "Edit Advertisements\n ", CheckCommandAccess(client, "server_redirect_edit_advertisements", ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
	
	int iNumOfPublicCategories 	= LoadMenuCategories(mServerList, client);
	int iNumOfPublicServers 	= LoadMenuServers(mServerList, client, "");
	
	if(iNumOfPublicServers + iNumOfPublicCategories == 0)
		CPrintToChat(client, "%t", "NoServersFound", PREFIX);
	
	mServerList.ExitButton = true;
	
	mServerList.Display(client, MENU_TIME_FOREVER);
}

// Command_ServerList menu Menu-Handler
public int ServerListMenuHandler(Menu ListMenu, MenuAction action, int client, int Clicked)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- ServerListMenuHandler");
	
	switch(action)
	{
		case MenuAction_Select:
		{
			char sBuffer[MAX_BUFFER_SIZE];
			ListMenu.GetItem(Clicked, sBuffer, sizeof(sBuffer));
			
			if(Clicked == 0 && StrEqual(sBuffer, "EditAdvertisements"))
			{
				Command_EditServerRedirectAdvertisements(client, 0);
				return 0;
			}
			
			if(StrContains(sBuffer, "[C]") != -1)
			{
				LoadCategoryMenu(client, sBuffer[4]);
			}
			else
			{
				char ServerIP[4][4], cServerID[4];
				strcopy(cServerID, sizeof(cServerID), sBuffer);
				int iServer = StringToInt(sBuffer);
				
				GetIPv4FromIP32(g_srOtherServers[iServer].iServerIP32, ServerIP);
				bool bIsServerFull = g_srOtherServers[iServer].iNumOfPlayers >= g_srOtherServers[iServer].iMaxPlayers;
				
				Menu mServerInfo = new Menu(ServerInfoMenuHandler);
				mServerInfo.SetTitle("%s [%s.%s.%s.%s:%d]", g_srOtherServers[iServer].sServerName, ServerIP[0], ServerIP[1], ServerIP[2], ServerIP[3], g_srOtherServers[iServer].iServerPort);
				
				mServerInfo.AddItem("", "", ITEMDRAW_SPACER);
				
				Format(sBuffer, sizeof(sBuffer), "%t", "NumberOfPlayersMenu", g_srOtherServers[iServer].iNumOfPlayers, g_srOtherServers[iServer].iMaxPlayers, bIsServerFull ? "[FULL]" : "");
				mServerInfo.AddItem(cServerID, sBuffer, ITEMDRAW_DISABLED);
				
				Format(sBuffer, sizeof(sBuffer), "%t", "ServerMapMenu", g_srOtherServers[iServer].sServerMap);
				mServerInfo.AddItem(cServerID, sBuffer, ITEMDRAW_DISABLED);
				
				mServerInfo.AddItem("", "", ITEMDRAW_SPACER);
				
				Format(sBuffer, sizeof(sBuffer), "%t", "PrintInfoMenu");
				mServerInfo.AddItem(cServerID, sBuffer);
				
				Format(sBuffer, sizeof(sBuffer), "%t", "JoinServerMenu");
				mServerInfo.AddItem(cServerID, sBuffer, !bIsServerFull || CheckCommandAccess(client, "server_redirect_join_full_bypass", ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
				
				mServerInfo.ExitButton = true;
			
				mServerInfo.Display(client, MENU_TIME_FOREVER);
			}
		}
		case MenuAction_Cancel:
			if(Clicked == MenuCancel_ExitBack)
				Command_ServerList(client, 0);
		case MenuAction_End:
			delete ListMenu;
	}
	
	return 0;
}

// ServerListMenuHandler menu Menu-Handler
public int ServerInfoMenuHandler(Menu ServerInfoMenu, MenuAction action, int client, int Clicked)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- ServerInfoMenuHandler");
	
	char cServerID[3];
	ServerInfoMenu.GetItem(4, cServerID, sizeof(cServerID));
	int iServer = StringToInt(cServerID);
	
	switch(action)
	{
		case MenuAction_Select:
		{
			if(Clicked == 4)
			{
				char ServerIP[4][4];
				GetIPv4FromIP32(g_srOtherServers[iServer].iServerIP32, ServerIP);
				
				CPrintToChat(client, "%t", "ServerInfoHeadline"	, PREFIX, g_srOtherServers[iServer].sServerName);
				CPrintToChat(client, "%t", "ServerInfoIP"		, PREFIX, ServerIP[0], ServerIP[1], ServerIP[2], ServerIP[3], g_srOtherServers[iServer].iServerPort);
				CPrintToChat(client, "%t", "ServerInfoMap"		, PREFIX, g_srOtherServers[iServer].sServerMap);
				CPrintToChat(client, "%t", "ServerInfoPlayers"	, PREFIX, g_srOtherServers[iServer].iNumOfPlayers, g_srOtherServers[iServer].iMaxPlayers);
			}
			else
				RedirectClientOnServer(client, g_srOtherServers[iServer].iServerIP32, g_srOtherServers[iServer].iServerPort);
		}
		case MenuAction_Cancel:
		{
			if (!StrEqual(g_srOtherServers[iServer].sServerCategory, "", false))
				LoadCategoryMenu(client, g_srOtherServers[iServer].sServerCategory);
			else
				Command_ServerList(client, 0);
		}
		case MenuAction_End:
			delete ServerInfoMenu;
	}
}

//==================================[ HELPING ]==============================//
// Update other servers
stock void LoadServers()
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadServers");
	
	DB.Format(Query, sizeof(Query), "SELECT * FROM `server_redirect_servers` WHERE `server_id` != %d ORDER BY `server_id`", g_srCurrentServer.iServerID);
	
	if(g_cvPrintDebug.BoolValue)
		LogMessage("[LoadServers] Query: %s", Query);
	
	
	DB.Query(T_OnServersReceive, Query);
}

// Clean other servers array
stock void CleanServersArray(int iStart)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- CleanServersArray | Cleaned the array from the %d index to the end", iStart);
		
	Server CleanServer;
	
	for (int iCurrentServer = iStart; iCurrentServer < MAX_SERVERS; iCurrentServer++)
		g_srOtherServers[iCurrentServer] = CleanServer;
}

// Load Category-Menu
stock void LoadCategoryMenu(int client, char[] sCategory)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadCategoryMenu");
	
	Menu mServerCategoryList = new Menu(ServerListMenuHandler);
	mServerCategoryList.SetTitle("%t", "MenuTitleCategory", PREFIX_NO_COLOR, sCategory);
	
	int iNumOfPublicServers = LoadMenuServers(mServerCategoryList, client, sCategory);
	
	if(iNumOfPublicServers == 0)
		CPrintToChat(client, "%t", "NoServersFound", PREFIX);
					
	mServerCategoryList.ExitButton = true;
	mServerCategoryList.ExitBackButton = true;
			
	mServerCategoryList.Display(client, MENU_TIME_FOREVER);
}

// Load servers into a menu
stock int LoadMenuServers(Menu mMenu, int client, char[] sCategory)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadMenuServers");
	
	int iNumOfPublicServers = 0;
	for (int iCurrentServer = 0; iCurrentServer < MAX_SERVERS; iCurrentServer++)
	{
		if(StrEqual(g_srOtherServers[iCurrentServer].sServerName, "", false) || !StrEqual(g_srOtherServers[iCurrentServer].sServerCategory, sCategory, false) ||!ClientCanAccessToServer(client, iCurrentServer))
			continue;
		
		char sServerShowString[MAX_BUFFER_SIZE];
		
		if(g_srOtherServers[iCurrentServer].bServerStatus)
		{
			strcopy(sServerShowString, sizeof(sServerShowString), g_sMenuFormat); // Size 9
			
			FormatStringWithServerProperties(sServerShowString, sizeof(sServerShowString), iCurrentServer);
			
			if(g_srOtherServers[iCurrentServer].iNumOfPlayers >= g_srOtherServers[iCurrentServer].iMaxPlayers)
				Format(sServerShowString, sizeof(sServerShowString), "%t", "ServerFullMenu", sServerShowString); // Size 7
		}
		else
			Format(sServerShowString, sizeof(sServerShowString), "%t", "ServerOfflineMenu", g_srOtherServers[iCurrentServer].sServerName);  // Size 17
		
		if(!g_srOtherServers[iCurrentServer].bShowInServerList)
			Format(sServerShowString, sizeof(sServerShowString), "%t", "ServerHiddenMenu", sServerShowString); // Size 9
		
		char cServerID[3];
		IntToString(iCurrentServer, cServerID, sizeof(cServerID));
		
		mMenu.AddItem(cServerID, sServerShowString, g_srOtherServers[iCurrentServer].bServerStatus ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		iNumOfPublicServers++;
	}
	return iNumOfPublicServers;
}

// Format a string with server properties.
stock void FormatStringWithServerProperties(char[] sToFormat, int iStringSize, int iServerIndex)
{
	// SERVER NAME
	ReplaceString(sToFormat, iStringSize, "{name}", g_srOtherServers[iServerIndex].sServerName, false); // Max size 30
	
	// SERVER CATEGORY
	ReplaceString(sToFormat, iStringSize, "{category}", g_srOtherServers[iServerIndex].sServerCategory, false); // Max size 30
	
	// SERVER MAP
	ReplaceString(sToFormat, iStringSize, "{map}", g_srOtherServers[iServerIndex].sServerMap , false); // Max size 15
	
	// SERVER STATUS
	ReplaceString(sToFormat, iStringSize, "{status}", g_srOtherServers[iServerIndex].bServerStatus ? "ONLINE" : "OFFLINE" , false); // Max size 15
	
	// BOTS INCLUDED
	ReplaceString(sToFormat, iStringSize, "{bots}", g_srOtherServers[iServerIndex].bServerStatus ? "Players & Bots" : "Real Players" , false); // Max size 15
	
	// SERVER IP
	char sServerIPv4[4][4], sFullIPv4[17];
	GetIPv4FromIP32(g_srOtherServers[iServerIndex].iServerIP32, sServerIPv4);
	Format(sFullIPv4, sizeof(sFullIPv4), "%s.%s.%s.%s", sFullIPv4[0], sFullIPv4[1], sFullIPv4[2], sFullIPv4[3]);
	ReplaceString(sToFormat, iStringSize, "{ip}", sFullIPv4, false);
	
	// SERVER ID (DB ID)
	ReplaceStringWithInt(sToFormat, iStringSize, "{id}", g_srOtherServers[iServerIndex].iServerID, false);
	
	// SERVER PORT
	ReplaceStringWithInt(sToFormat, iStringSize, "{port}", g_srOtherServers[iServerIndex].iServerPort, false);
	
	// CURRENT SERVER PLAYERS
	ReplaceStringWithInt(sToFormat, iStringSize, "{current}", g_srOtherServers[iServerIndex].iNumOfPlayers, false); // Size 2
	
	// MAX SERVER PLAYERS
	ReplaceStringWithInt(sToFormat, iStringSize, "{max}", g_srOtherServers[iServerIndex].iMaxPlayers, false); // Size 2
}

// ReplaceString() with an Int type instead of String (char[])
stock void ReplaceStringWithInt(char[] sDest, int iDestSize, char[] sToReplace, int iValueToReplaceWith, bool bCaseSensitive = true)
{
	char sIntToString[64];
	
	IntToString(iValueToReplaceWith, sIntToString, sizeof(sIntToString));
	ReplaceString(sDest, iDestSize, sToReplace, sIntToString, bCaseSensitive);
}

// Load Categories into a menu
stock int LoadMenuCategories(Menu mMenu, int client)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadMenuCategories");
	
	int iNumOfPublicCategories = 0;
	
	for (int iCurrentServer = 0; iCurrentServer < MAX_SERVERS; iCurrentServer++)
	{
		if(StrEqual(g_srOtherServers[iCurrentServer].sServerCategory, "", false) || CategoryAlreadyExist(iCurrentServer) || !ClientCanAccessToServer(client, iCurrentServer))
			continue;
			
		char sBuffer[MAX_BUFFER_SIZE];
		Format(sBuffer, sizeof(sBuffer), "[C] %s", g_srOtherServers[iCurrentServer].sServerCategory);
		
		mMenu.AddItem(sBuffer, sBuffer);
		iNumOfPublicCategories++;
	}
	
	return iNumOfPublicCategories;
}

// Check if Category already exists
stock bool CategoryAlreadyExist(int iServer)
{
	for (int iCurrentServer = 0; iCurrentServer < iServer; iCurrentServer++)
		if(StrEqual(g_srOtherServers[iCurrentServer].sServerCategory, g_srOtherServers[iServer].sServerCategory, false))
			return true;
	return false;
}

// Check if the client should have access to the server //
stock bool ClientCanAccessToServer(int client, int iServer)
{
	return (g_srOtherServers[iServer].bShowInServerList || CheckCommandAccess(client, "server_redirect_show_hidden_servers", ADMFLAG_ROOT));
}