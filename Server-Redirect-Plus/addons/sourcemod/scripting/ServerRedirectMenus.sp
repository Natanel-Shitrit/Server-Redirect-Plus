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

public Plugin myinfo = 
{
	name = "[Server-Redirect+] Menus", 
	author = "Natanel 'LuqS'", 
	description = "Menus of 'Server-Redirect+', Loading the information of all other servers and displaying them in the menu.", 
	version = "2.3.0", 
	url = "https://steamcommunity.com/id/luqsgood | Discord: LuqS#6505"
};

// SQL Callback for LoadServers()
void T_OnServersReceive(Handle owner, Handle hQuery, const char[] sError, any bFirstLoad)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnServersReceive");
	
	// If we got a respond lets fetch the data and store it
	if (hQuery != INVALID_HANDLE)
	{
		bool bServerGotDeleted;
		
		// We are going to loop through all the server we got
		int iCurrentServer;
		for (iCurrentServer = 0; iCurrentServer < MAX_SERVERS && SQL_FetchRow(hQuery); iCurrentServer++)
		{
			g_srOtherServers[iCurrentServer].iServerSteamAID = SQL_FetchInt(hQuery, SQL_FIELD_SERVER_STEAM_ID);
			
			int iServerTimeOut = SQL_FetchInt(hQuery, SQL_FIELD_SERVER_TIMEOUT) * 60;
			if(iServerTimeOut > 0)
			{
				int iServerLastUpdate 		 = SQL_FetchInt(hQuery, SQL_FIELD_SERVER_LAST_UPDATE_UNIX);
				int iServerTimeWithoutUpdate = GetTime() - iServerLastUpdate;
				
				if(iServerTimeWithoutUpdate >= iServerTimeOut)
				{
					bServerGotDeleted = true;
					
					Format(Query, sizeof(Query), "DELETE FROM `server_redirect_servers` WHERE `server_steam_id` = %d", g_srOtherServers[iCurrentServer].iServerSteamAID);
					
					if (g_cvPrintDebug.BoolValue)
						LogMessage("Delete Server Query: %s", Query);
						
					DB.Query(T_FakeFastQuery, Query, _, DBPrio_Low);
					
					if (g_cvPrintDebug.BoolValue)
						LogMessage("Deleting Server (Server Steam ID - %d | Last update - %d | timeout time in sec - %d | time without update %d)",
							g_srOtherServers[iCurrentServer].iServerSteamAID,
							iServerLastUpdate,
							iServerTimeOut,
							iServerTimeWithoutUpdate
						);
					
					iCurrentServer--;
					continue;
				}
			}
			
			// Store everything that we get from the database 
			g_srOtherServers[iCurrentServer].iServerIP32 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_IP);
			g_srOtherServers[iCurrentServer].iServerPort 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_PORT);
			g_srOtherServers[iCurrentServer].iReservedSlots = SQL_FetchInt(hQuery, SQL_FIELD_SERVER_RESERVED_SLOTS);
			
			g_srOtherServers[iCurrentServer].bServerStatus 		= view_as<bool>(SQL_FetchInt(hQuery, SQL_FIELD_SERVER_STATUS));
			g_srOtherServers[iCurrentServer].bShowInServerList 	= view_as<bool>(SQL_FetchInt(hQuery, SQL_FIELD_SERVER_VISIBLE));
			g_srOtherServers[iCurrentServer].bHiddenSlots		= view_as<bool>(SQL_FetchInt(hQuery, SQL_FIELD_SERVER_HIDDEN_SLOTS));
			g_srOtherServers[iCurrentServer].bIncludeBots 		= view_as<bool>(SQL_FetchInt(hQuery, SQL_FIELD_SERVER_INCLUD_BOTS));
			
			SQL_FetchString(hQuery, SQL_FIELD_SERVER_NAME, g_srOtherServers[iCurrentServer].sServerName, sizeof(g_srOtherServers[].sServerName));
			SQL_FetchString(hQuery, SQL_FIELD_SERVER_CATEGORY, g_srOtherServers[iCurrentServer].sServerCategory, sizeof(g_srOtherServers[].sServerCategory));
			
			// if the server is offline we don't want to load real-time data because it's not real-time (outdated),
			// And we don't want to advertise Map-Changes / Player-Range Advertisements.
			if (g_srOtherServers[iCurrentServer].bServerStatus)
			{
				g_srOtherServers[iCurrentServer].iNumOfPlayers 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_PLAYERS);
				g_srOtherServers[iCurrentServer].iMaxPlayers 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_MAX_PLAYERS);
				
				char sOldMap[PLATFORM_MAX_PATH];
				if (!StrEqual(g_srOtherServers[iCurrentServer].sServerMap, "", false))
					strcopy(sOldMap, sizeof(sOldMap), g_srOtherServers[iCurrentServer].sServerMap);
				
				SQL_FetchString(hQuery, SQL_FIELD_SERVER_MAP, g_srOtherServers[iCurrentServer].sServerMap, sizeof(g_srOtherServers[].sServerMap));
				
				if(g_bAdvertisementsAreEnabled && !bFirstLoad)
				{
					int iServerAdvertisement = FindAdvertisement(g_srOtherServers[iCurrentServer].iServerSteamAID, ADVERTISEMENT_PLAYERS_RANGE);
				
					if (iServerAdvertisement != -1 && g_advAdvertisements[iServerAdvertisement].iPlayersRange[0] <= g_srOtherServers[iCurrentServer].iNumOfPlayers <= g_advAdvertisements[iServerAdvertisement].iPlayersRange[1])
						PostAdvertisement(g_srOtherServers[iCurrentServer].iServerSteamAID, ADVERTISEMENT_PLAYERS_RANGE);
					
					if (!StrEqual(sOldMap, g_srOtherServers[iCurrentServer].sServerMap))
						PostAdvertisement(g_srOtherServers[iCurrentServer].iServerSteamAID, ADVERTISEMENT_MAP);
				}
			}
			
			if (g_cvPrintDebug.BoolValue)
				LogMessage("[T_OnServersReceive -> LOOP(%d) -> IF] Server Steam ID %d (Status: %b | Show: %b): \nName: %s, Category: %s, Map: %s, IP32: %d, Port: %d, Number of players: %d, Max players: %d",
					iCurrentServer,
					g_srOtherServers[iCurrentServer].iServerSteamAID,
					g_srOtherServers[iCurrentServer].bServerStatus,
					g_srOtherServers[iCurrentServer].bShowInServerList,
					g_srOtherServers[iCurrentServer].sServerName, 
					g_srOtherServers[iCurrentServer].sServerCategory, 
					g_srOtherServers[iCurrentServer].sServerMap, 
					g_srOtherServers[iCurrentServer].iServerIP32, 
					g_srOtherServers[iCurrentServer].iServerPort, 
					g_srOtherServers[iCurrentServer].iNumOfPlayers, 
					g_srOtherServers[iCurrentServer].iMaxPlayers
				);
			
		}
		
		if(!bFirstLoad)
		{
			// Clean the rest of the array so we won't show servers that got deleted in the database and still somewhere in the array we didn't touch.
			CleanServersArray(iCurrentServer);
			
			// Reload Advertisements if a server got deleted.
			if(g_bAdvertisementsAreEnabled && bServerGotDeleted)
				LoadAdvertisements();
		}
		else // Create Advertisements Table on First-Load.
			CreateAdvertisementsTable();
			
		if (g_cvPrintDebug.BoolValue && !iCurrentServer)
			LogError("No servers found in DB.");
		
		if (g_cvPrintDebug.BoolValue && SQL_FetchRow(hQuery))
			LogError("%s There is more servers in SQL-Database server than MAX_SERVERS, please recompile it with MAX_SERVERS with a greater amount.", PREFIX_NO_COLOR);
	}
	else
		LogError("T_OnServersReceive Error: %s", sError);
}

//==================================[ MENUS & HANDLES ]==============================//
public Action Command_ServerList(int client, int args)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Command_ServerList | Fired by %N (%d)", client, client);
		
	char sMenuTitle[128];
	Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MenuTitleMain", PREFIX_NO_COLOR);
	
	SelectServerMainMenu(client, ServerListMenuHandler, g_sMenuFormat, sMenuTitle, strlen(sMenuTitle), true);
	
	return Plugin_Handled;
}

// Command_ServerList menu Menu-Handler
int ServerListMenuHandler(Menu ListMenu, MenuAction action, int client, int Clicked)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- ServerListMenuHandler");
	
	switch (action)
	{
		case MenuAction_Select:
		{
			// Get the menu item info from where the client clicked
			char sMenuItemInfo[MAX_CATEGORY_NAME_LENGHT];
			ListMenu.GetItem(Clicked, sMenuItemInfo, sizeof(sMenuItemInfo));
			
			if (StrEqual(sMenuItemInfo, "EditAdvertisements"))		// If it was the edit advertisement button, open the edit menu.
				OpenEditServerRedirectAdvertisementsMenu(client);
			else if (String_StartsWith(sMenuItemInfo, "[C]")) 		// If it was a category, show the category servers
				LoadCategoryMenu(client, sMenuItemInfo[4]);
				
			// If we ended up here the client clicked on a server, let's prepare the server menu.
			else
			{
				// Get the Server-ID from the item info we got earlier.
				char cServerID[4];
				strcopy(cServerID, sizeof(cServerID), sMenuItemInfo);
				
				// Save it as int, we will use that also.
				int iServer = StringToInt(sMenuItemInfo);
				
				// Get the server IP as 'xxx.xxx.xxx.xxx' from IP32
				char ServerIP[4][4];
				GetIPv4FromIP32(g_srOtherServers[iServer].iServerIP32, ServerIP);
				
				// Now we finally create the menu, also format the title.
				Menu mServerInfo = new Menu(ServerInfoMenuHandler);
				mServerInfo.SetTitle("%s [%s.%s.%s.%s:%d]\n ", g_srOtherServers[iServer].sServerName, ServerIP[0], ServerIP[1], ServerIP[2], ServerIP[3], g_srOtherServers[iServer].iServerPort);
				
				bool bCanUseReservedSlots = CanClientUseReservedSlots(client, iServer);
				int iMaxPlayerWithReserved = g_srOtherServers[iServer].iMaxPlayers - ((!g_srOtherServers[iServer].bHiddenSlots || bCanUseReservedSlots) ? 0 : g_srOtherServers[iServer].iReservedSlots);
				
				// Is the server full?
				bool bIsServerFull = g_srOtherServers[iServer].iNumOfPlayers >= iMaxPlayerWithReserved;
				
				char sEditBuffer[128];
				
				// Add 'Number of player'.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "NumberOfPlayersMenu", g_srOtherServers[iServer].iNumOfPlayers, iMaxPlayerWithReserved, bIsServerFull ? "ServerFullMenu" : "EmptyText");
				
				if(g_srOtherServers[iServer].iReservedSlots && (!g_srOtherServers[iServer].bHiddenSlots || bCanUseReservedSlots))
					Format(sEditBuffer, sizeof(sEditBuffer), "%s %t", sEditBuffer, "ServerReservedSlots", g_srOtherServers[iServer].iReservedSlots);
					
				mServerInfo.AddItem("", sEditBuffer, g_srOtherServers[iServer].bServerStatus ? ITEMDRAW_DISABLED : ITEMDRAW_IGNORE);
				
				// Add 'Map'.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t\n ", "ServerMapMenu", g_srOtherServers[iServer].sServerMap);
				mServerInfo.AddItem("", sEditBuffer, g_srOtherServers[iServer].bServerStatus ? ITEMDRAW_DISABLED : ITEMDRAW_IGNORE);
				
				// Add clickable option to print the info.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "PrintInfoMenu");
				mServerInfo.AddItem("", sEditBuffer);
				
				// Add clickable option to join the server.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "JoinServerMenu");
				
				if(!g_srOtherServers[iServer].bServerStatus)
					Format(sEditBuffer, sizeof(sEditBuffer), "%s %t", sEditBuffer, "ServerOfflineMenu");
				
				mServerInfo.AddItem(cServerID, sEditBuffer, g_srOtherServers[iServer].bServerStatus && (!bIsServerFull || CheckCommandAccess(client, "server_redirect_join_full_bypass", ADMFLAG_ROOT)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
				
				// Option to exit to the server category menu (Or to the main menu if there is no category)
				mServerInfo.ExitButton = true;
				
				// Display the menu.
				mServerInfo.Display(client, MENU_TIME_FOREVER);
			}
		}
		case MenuAction_Cancel:
		{
			char sFirstMenuItemInfoBuffer[32];
			ListMenu.GetItem(0, sFirstMenuItemInfoBuffer, sizeof(sFirstMenuItemInfoBuffer));
			
			if (Clicked == MenuCancel_Exit && !StrEqual(sFirstMenuItemInfoBuffer, "EditAdvertisements") && !StrEqual(g_srOtherServers[StringToInt(sFirstMenuItemInfoBuffer)].sServerCategory, ""))
				Command_ServerList(client, 0);
		}
		case MenuAction_End:
		{
			delete ListMenu;
		}
	}
}

// ServerListMenuHandler menu Menu-Handler
int ServerInfoMenuHandler(Menu ServerInfoMenu, MenuAction action, int client, int Clicked)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- ServerInfoMenuHandler");
	
	// Get the Server-ID from the 'Join Server' item info buffer (index 3)
	char cServerID[4];
	ServerInfoMenu.GetItem(3, cServerID, sizeof(cServerID));
	
	// Get Server-ID as int
	int iServer = StringToInt(cServerID);
	
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (Clicked)
			{
				// Clicked on 'Print info' button.
				case 2:
				{
					char ServerIP[4][4];
					GetIPv4FromIP32(g_srOtherServers[iServer].iServerIP32, ServerIP);
					
					CPrintToChat(client, "%t", "ServerInfoHeadline"	, PREFIX, g_srOtherServers[iServer].sServerName);
					CPrintToChat(client, "%t", "ServerInfoIP"		, PREFIX, ServerIP[0], ServerIP[1], ServerIP[2], ServerIP[3], g_srOtherServers[iServer].iServerPort);
					
					if(g_srOtherServers[iServer].bServerStatus)
					{
						CPrintToChat(client, "%t", "ServerInfoMap"		, PREFIX, g_srOtherServers[iServer].sServerMap);
						CPrintToChat(client, "%t", "ServerInfoPlayers"	, PREFIX, g_srOtherServers[iServer].iNumOfPlayers, g_srOtherServers[iServer].iMaxPlayers - ((!g_srOtherServers[iServer].bHiddenSlots || CanClientUseReservedSlots(client, iServer)) ? 0 : g_srOtherServers[iServer].iReservedSlots));
					}
					
				}
				// Clicked on the redirect / join button.
				case 3:
				{
					RedirectClientOnServer(client, g_srOtherServers[iServer].iServerIP32, g_srOtherServers[iServer].iServerPort);
				}
			}
		}
		case MenuAction_Cancel:
		{
			// Exit back to the menu (if was in a category - to the category, else - to the main menu)
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
void LoadServers(bool bFirstLoad = false)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadServers | bFirstLoad = %b", bFirstLoad);
	
	DB.Format(Query, sizeof(Query), "SELECT *, UNIX_TIMESTAMP(unix_lastupdate) FROM `server_redirect_servers` WHERE `server_steam_id` != %d ORDER BY `server_backup_id`", g_srThisServer.iServerSteamAID);
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("[LoadServers] Query: %s", Query);
	
	DB.Query(T_OnServersReceive, Query, bFirstLoad);
}

// Clean other servers array
void CleanServersArray(int iStart)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- CleanServersArray | Cleaned the array from the %d index to the end", iStart);
	
	Server CleanServer;
	
	for (int iCurrentServer = iStart; iCurrentServer < MAX_SERVERS; iCurrentServer++)
		g_srOtherServers[iCurrentServer] = CleanServer;
}

// Load Category-Menu
void LoadCategoryMenu(int client, char[] sCategory)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadCategoryMenu");
	
	char sMenuTitle[128];
	Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MenuTitleCategory", PREFIX_NO_COLOR, sCategory);
	SelectServerMenu(client, sCategory, g_sMenuFormat, ServerListMenuHandler, sMenuTitle, strlen(sMenuTitle));
}

// Load Category-Menu
void SelectServerMenu(int client, const char[] sCategory, const char[] sMenuFormat, MenuHandler hMenuHandlerToUse, const char[] sTitle, int iTitleLength)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- SelectServerMenu");

	Menu mServerCategoryList = new Menu(hMenuHandlerToUse);

	mServerCategoryList.SetTitle(sTitle);

	int iNumOfPublicServers = LoadMenuServers(mServerCategoryList, client, sMenuFormat, sCategory, iTitleLength);

	if(iNumOfPublicServers == 0)
		CPrintToChat(client, "%t", "NoServersFound", PREFIX);

	mServerCategoryList.ExitButton = true;

	mServerCategoryList.Display(client, MENU_TIME_FOREVER);
}

// Load Servers to choose from them
void SelectServerMainMenu(int client, MenuHandler mMenuHandlerToUse, const char[] sMenuFormat, const char[] sTitle, int iTitleLength, bool bAddEditAdvButton)
{
	Menu mServerList = new Menu(mMenuHandlerToUse);
	mServerList.SetTitle(sTitle);
	
	if(bAddEditAdvButton)
	{
		char sTranslationTextBuffer[32];
		Format(sTranslationTextBuffer, sizeof(sTranslationTextBuffer), "%t\n ", "EditAdvertisementsMenuItem");
		mServerList.AddItem("EditAdvertisements", sTranslationTextBuffer, CheckCommandAccess(client, "server_redirect_edit_advertisements", ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
	}
		
	int iNumOfPublicCategories 	= LoadMenuCategories(mServerList, client);
	int iNumOfPublicServers 	= LoadMenuServers(mServerList, client, sMenuFormat, "", iTitleLength);
	
	if(iNumOfPublicServers + iNumOfPublicCategories == 0)
		CPrintToChat(client, "%t", "NoServersFound", PREFIX);
	
	mServerList.ExitButton = true;
	
	mServerList.Display(client, MENU_TIME_FOREVER);
}

// Load servers into a menu
int LoadMenuServers(Menu mMenu, int client, const char[] sMenuFormat, const char[] sCategory, int iTitleLenght)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadMenuServers");
	
	int iStringSize = (464 - iTitleLenght) / 6;
	
	char[] sServerShowString = new char[iStringSize];
	
	int iNumOfPublicServers = 0;
	for (int iCurrentServer = 0; iCurrentServer < MAX_SERVERS; iCurrentServer++)
	{
		if (StrEqual(g_srOtherServers[iCurrentServer].sServerName, "", false) || !StrEqual(g_srOtherServers[iCurrentServer].sServerCategory, sCategory, false) || !ClientCanAccessToServer(client, iCurrentServer))
			continue;
		
		strcopy(sServerShowString, iStringSize, sMenuFormat);
		
		if (!g_srOtherServers[iCurrentServer].bShowInServerList)
			Format(sServerShowString, iStringSize, "%s %t", sServerShowString, "ServerHiddenMenu");
		
		if (g_srOtherServers[iCurrentServer].bServerStatus)
		{
			if (g_srOtherServers[iCurrentServer].iNumOfPlayers >= g_srOtherServers[iCurrentServer].iMaxPlayers - ((!g_srOtherServers[iCurrentServer].bHiddenSlots || CanClientUseReservedSlots(client, iCurrentServer)) ? 0 : g_srOtherServers[iCurrentServer].iReservedSlots))
				Format(sServerShowString, iStringSize, "%s %t", sServerShowString, "ServerFullMenu");
				
			FormatStringWithServerProperties(sServerShowString, iStringSize + 1, iCurrentServer, client);
		}
		else
			Format(sServerShowString, iStringSize, "%s %t", g_srOtherServers[iCurrentServer].sServerName, "ServerOfflineMenu");
		
		char cServerID[3];
		IntToString(iCurrentServer, cServerID, sizeof(cServerID));
		
		mMenu.AddItem(cServerID, sServerShowString);
		iNumOfPublicServers++;
	}
	
	return iNumOfPublicServers;
}

// Get the size of just the template witout the properties.
int GetEmptyFormatStringSize(const char[] sFormatString, int iFormatStringLenght)
{
	// Get the full template.
	char[] sFullFormatString = new char[iFormatStringLenght];
	strcopy(sFullFormatString, iFormatStringLenght, sFormatString);
	
	// What we want to get rid of.
	char sToReplace[][] =  { "{shortname}", "{longname}", "{category}", "{map}", "{status}", "{bots}", "{ip}", "{id}", "{port}", "{current}", "{max}" };
	
	// Loop through this and remove each string.
	for (int iCurrentStringToReplace = 0; iCurrentStringToReplace < sizeof(sToReplace); iCurrentStringToReplace++)
		ReplaceString(sFullFormatString, iFormatStringLenght, sToReplace[iCurrentStringToReplace], "");
	
	// return the lenght of the template.
	return strlen(sFullFormatString);
}

// Formats a string with server properties.
void FormatStringWithServerProperties(char[] sToFormat, int iStringSize, int iServerIndex, int client = -1)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- FormatStringWithServerProperties");
	
	// used to calculate how many characters we have left so we will not have oversized string.
	int iFormatSizeLeft = iStringSize - GetEmptyFormatStringSize(sToFormat, iStringSize);
	
	// for each property, the number of characters in use will be subtracted from the variable that stores the number of characters left.
	
	// SERVER ID (DB ID)
	iFormatSizeLeft -= ReplaceStringWithInt(sToFormat, iStringSize, "{id}", g_srOtherServers[iServerIndex].iServerSteamAID, false);
	
	// SERVER PORT
	iFormatSizeLeft -= ReplaceStringWithInt(sToFormat, iStringSize, "{port}", g_srOtherServers[iServerIndex].iServerPort, false);
	
	// CURRENT SERVER PLAYERS
	iFormatSizeLeft -= ReplaceStringWithInt(sToFormat, iStringSize, "{current}", g_srOtherServers[iServerIndex].iNumOfPlayers, false);
	
	// MAX SERVER PLAYERS 
	iFormatSizeLeft -= ReplaceStringWithInt(sToFormat, iStringSize, "{max}", g_srOtherServers[iServerIndex].iMaxPlayers - ((!g_srOtherServers[iServerIndex].bHiddenSlots || CanClientUseReservedSlots(client, iServerIndex)) ? 0 : g_srOtherServers[iServerIndex].iReservedSlots), false);
	
	// SERVER IP - SIZE 16
	char sServerIPv4[4][4], sFullIPv4[17];
	GetIPv4FromIP32(g_srOtherServers[iServerIndex].iServerIP32, sServerIPv4);
	ImplodeStrings(sServerIPv4, 4, ".", sFullIPv4, sizeof(sFullIPv4));
	iFormatSizeLeft -= 16 * ReplaceString(sToFormat, iStringSize, "{ip}", sFullIPv4, false);
	
	// SERVER STATUS - SIZE 7
	iFormatSizeLeft -= 7 * ReplaceString(sToFormat, iStringSize, "{status}", g_srOtherServers[iServerIndex].bServerStatus ? "ONLINE" : "OFFLINE", false);
	
	// BOTS INCLUDED - SIZE 14
	iFormatSizeLeft -= 14 * ReplaceString(sToFormat, iStringSize, "{bots}", g_srOtherServers[iServerIndex].bIncludeBots ? "Players & Bots" : "Real Players", false);
	
	// How many characters we ended out with?
	if (g_cvPrintDebug.BoolValue)
		LogMessage("Characters left: %d", iFormatSizeLeft);
	
	// Calculate for how many string are in use
	int iNumOfStringPropertiesUsed = rgCountStrings.MatchAll(sToFormat);
	
	// If there is no strings in use, just skip this part.
	if (iNumOfStringPropertiesUsed > 0)
	{
		// Get how many characters will be used for each string
		char[] sReplaceBuffer = new char[iFormatSizeLeft];
		int iNumOfFreeCharacters = 0, iClaculateBuffer = 0, iLenghtForEachProperty = iFormatSizeLeft / iNumOfStringPropertiesUsed;
		
		// Just for the name we will get the full lengh and if we need to remove any string / prefix we will do it here.
		char sShortServerName[MAX_SERVER_NAME_LENGHT];
		strcopy(sShortServerName, sizeof(sShortServerName), g_srOtherServers[iServerIndex].sServerName);
		
		// Remove the Prefix string
		if (!StrEqual(g_sPrefixRemover, "", false))
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Removing '%s' from '%s'", g_sPrefixRemover, sShortServerName);
			
			ReplaceString(sShortServerName, sizeof(sShortServerName), g_sPrefixRemover, "", true);
		}
		
		// SERVER CATEGORY - MAX SIZE 64
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty, g_srOtherServers[iServerIndex].sServerCategory);
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{category}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER MAP - MAX SIZE 64
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty, g_srOtherServers[iServerIndex].sServerMap);
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{map}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER SHORT NAME - MAX SIZE <= FULL NAME
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty + (iNumOfFreeCharacters > 0 ? iNumOfFreeCharacters : 0), sShortServerName);
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{shortname}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER FULL NAME - MAX SIZE 245
		CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty + (iNumOfFreeCharacters > 0 ? iNumOfFreeCharacters : 0), g_srOtherServers[iServerIndex].sServerName);
		ReplaceString(sToFormat, iStringSize, "{longname}", sReplaceBuffer, false);
	}
}

// ReplaceString() with an Int type instead of String (char[])
int ReplaceStringWithInt(char[] sDest, int iDestSize, char[] sToReplace, int iValueToReplaceWith, bool bCaseSensitive = true)
{
	char sIntToString[128];
	return IntToString(iValueToReplaceWith, sIntToString, sizeof(sIntToString)) * ReplaceString(sDest, iDestSize, sToReplace, sIntToString, bCaseSensitive);
}

// Load Categories into a menu
int LoadMenuCategories(Menu mMenu, int client)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadMenuCategories");
	
	int iNumOfPublicCategories = 0;
	
	for (int iCurrentServer = 0; iCurrentServer < MAX_SERVERS; iCurrentServer++)
	{
		if (StrEqual(g_srOtherServers[iCurrentServer].sServerCategory, "", false) || CategoryAlreadyExist(iCurrentServer) || !ClientCanAccessToServer(client, iCurrentServer))
			continue;
		
		char sBuffer[MAX_CATEGORY_NAME_LENGHT];
		Format(sBuffer, sizeof(sBuffer), "[C] %s", g_srOtherServers[iCurrentServer].sServerCategory);
		
		mMenu.AddItem(sBuffer, sBuffer);
		iNumOfPublicCategories++;
	}
	
	return iNumOfPublicCategories;
}

// Check if Category already exists
bool CategoryAlreadyExist(int iServer)
{
	for (int iCurrentServer = 0; iCurrentServer < iServer; iCurrentServer++)
		if (StrEqual(g_srOtherServers[iCurrentServer].sServerCategory, g_srOtherServers[iServer].sServerCategory, false))
			return true;
	
	return false;
}

// Check if the client should have access to the server
bool ClientCanAccessToServer(int client, int iServer)
{
	return (g_srOtherServers[iServer].bShowInServerList || CheckCommandAccess(client, "server_redirect_show_hidden_servers", ADMFLAG_ROOT));
}

// Check if the client should see reserved slots
bool CanClientUseReservedSlots(int client, int iServer)
{
	return (g_srOtherServers[iServer].iReservedSlots && CheckCommandAccess(client, "server_redirect_use_reserved_slots", ADMFLAG_ROOT));
} 