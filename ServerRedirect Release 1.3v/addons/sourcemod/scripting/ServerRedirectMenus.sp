enum
{
	SQL_FIELD_SERVER_ID = 1,
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
	SQL_FIELD_SERVER_TIMEOUT
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
public void T_OnServersReceive(Handle owner, Handle hQuery, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnServersReceive");
	
	// If we got a respond lets fetch the data and store it
	if (hQuery != INVALID_HANDLE)
	{
		// We are going to loop through all the server we got
		int iCurrentServer;
		for (iCurrentServer = 0; iCurrentServer < MAX_SERVERS && SQL_FetchRow(hQuery); iCurrentServer++)
		{
			// Store everything that we get from the database 
			g_srOtherServers[iCurrentServer].iServerID 	 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_ID);
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
				
				int iServerAdvertisement = FindAdvertisement(g_srOtherServers[iCurrentServer].iServerID, ADVERTISEMENT_PLAYERS_RANGE);
				
				if (iServerAdvertisement != -1 && g_advAdvertisements[iServerAdvertisement].iPlayersRange[0] < g_srOtherServers[iCurrentServer].iNumOfPlayers < g_advAdvertisements[iServerAdvertisement].iPlayersRange[1])
					PostAdvertisement(g_srOtherServers[iCurrentServer].iServerID, ADVERTISEMENT_PLAYERS_RANGE);
				
				char sOldMap[PLATFORM_MAX_PATH];
				if (!StrEqual(g_srOtherServers[iCurrentServer].sServerMap, "", false))
					strcopy(sOldMap, sizeof(sOldMap), g_srOtherServers[iCurrentServer].sServerMap);
			
				SQL_FetchString(hQuery, SQL_FIELD_SERVER_MAP, g_srOtherServers[iCurrentServer].sServerMap, sizeof(g_srOtherServers[].sServerMap));
			
				if (!StrEqual(sOldMap, g_srOtherServers[iCurrentServer].sServerMap))
					PostAdvertisement(g_srOtherServers[iCurrentServer].iServerID, ADVERTISEMENT_MAP);
			}
			
			// Check if the server is timed out (this will remove the server from the array)
			CheckIfServerTimedOut(g_srOtherServers[iCurrentServer].iServerID);
			
			if (g_cvPrintDebug.BoolValue)
				LogMessage("[T_OnServersReceive -> LOOP(%d) -> IF] Server-ID %d (Status: %b | Show: %b): \nName: %s, Category: %s, Map: %s, IP32: %d, Port: %d, Number of players: %d, Max players: %d",
				iCurrentServer,
				g_srOtherServers[iCurrentServer].iServerID,
				g_srOtherServers[iCurrentServer].bServerStatus,
				g_srOtherServers[iCurrentServer].bShowInServerList,
				g_srOtherServers[iCurrentServer].sServerName, 
				g_srOtherServers[iCurrentServer].sServerCategory, 
				g_srOtherServers[iCurrentServer].sServerMap, 
				g_srOtherServers[iCurrentServer].iServerIP32, 
				g_srOtherServers[iCurrentServer].iServerPort, 
				g_srOtherServers[iCurrentServer].iNumOfPlayers, 
				g_srOtherServers[iCurrentServer].iMaxPlayers);
			
		}
		// Clean the rest of the array so we won't show servers that got deleted in the database and still somewhere in the array we didn't touch.
		CleanServersArray(iCurrentServer);
		
		if (!iCurrentServer)
			LogError("No servers found in DB.");
		
		if (SQL_FetchRow(hQuery))
			LogError("%s There is more servers in SQL-Database server than MAX_SERVERS, please recompile it with MAX_SERVERS with greater amount.", PREFIX_NO_COLOR);
	}
	else
		LogError("Error: %s", sError);
}

// Timer for other servers update
public Action Timer_UpdateOtherServers(Handle timer)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Timer_UpdateOtherServers");
	
	if (GetClientCountEx(false) != 0)
	{
		if (g_cvPrintDebug.BoolValue)
			LogMessage("[Timer_UpdateOtherServers -> IF] Loading Servers");
		
		LoadServers();
	}
	else if (g_cvPrintDebug.BoolValue)
		LogMessage("[Timer_UpdateOtherServers -> ELSE] Not loading servers because server is empty.");
	
	return Plugin_Continue;
}

//==================================[ MENUS & HANDLES ]==============================//
public Action Command_ServerList(int client, int args)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Command_ServerList | Fired by %N (%d)", client, client);
		
	char sMenuTitle[128];
	Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MenuTitleMain", PREFIX_NO_COLOR);
	
	SelectServerMainMenu(client, ServerListMenuHandler, sMenuTitle, strlen(sMenuTitle), true);
	
	return Plugin_Handled;
}

// Command_ServerList menu Menu-Handler
public int ServerListMenuHandler(Menu ListMenu, MenuAction action, int client, int Clicked)
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
			
			if (Clicked == 0 && StrEqual(sMenuItemInfo, "EditAdvertisements"))	// If it was the edit advertisement button, open the edit menu.
				Command_EditServerRedirectAdvertisements(client, 0);
			else if (String_StartsWith(sMenuItemInfo, "[C]")) 					// If it was a category, show the category servers
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
				
				int iMaxPlayerWithReserved = g_srOtherServers[iServer].iMaxPlayers - ((!g_srOtherServers[iServer].bHiddenSlots || CanClientUseReservedSlots(client, iServer)) ? 0 : g_srOtherServers[iServer].iReservedSlots);
				
				// Is the server full?
				bool bIsServerFull = g_srOtherServers[iServer].iNumOfPlayers >= iMaxPlayerWithReserved;
				
				char sEditBuffer[64];
				
				// Add 'Number of player'.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "NumberOfPlayersMenu", g_srOtherServers[iServer].iNumOfPlayers, iMaxPlayerWithReserved, bIsServerFull ? "[FULL]" : "");
				mServerInfo.AddItem("", sEditBuffer, ITEMDRAW_DISABLED);
				
				// Add 'Map'.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t\n ", "ServerMapMenu", g_srOtherServers[iServer].sServerMap);
				mServerInfo.AddItem("", sEditBuffer, ITEMDRAW_DISABLED);
				
				// Add clickable option to print the info.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "PrintInfoMenu");
				mServerInfo.AddItem("", sEditBuffer);
				
				// Add clickable option to join the server.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "JoinServerMenu");
				mServerInfo.AddItem(cServerID, sEditBuffer, !bIsServerFull || CheckCommandAccess(client, "server_redirect_join_full_bypass", ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
				
				// Option to exit from the menu (if was in a category - to the main menu, else - just close the menu)
				mServerInfo.ExitButton = true;
				
				// Display the menu.
				mServerInfo.Display(client, MENU_TIME_FOREVER);
			}
		}
		case MenuAction_Cancel:
		{
			if (Clicked == MenuCancel_ExitBack)
				Command_ServerList(client, 0);
		}
		case MenuAction_End:
		{
			delete ListMenu;
		}
	}
}

// ServerListMenuHandler menu Menu-Handler
public int ServerInfoMenuHandler(Menu ServerInfoMenu, MenuAction action, int client, int Clicked)
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
					CPrintToChat(client, "%t", "ServerInfoMap"		, PREFIX, g_srOtherServers[iServer].sServerMap);
					CPrintToChat(client, "%t", "ServerInfoPlayers"	, PREFIX, g_srOtherServers[iServer].iNumOfPlayers, g_srOtherServers[iServer].iMaxPlayers - ((!g_srOtherServers[iServer].bHiddenSlots || CanClientUseReservedSlots(client, iServer)) ? 0 : g_srOtherServers[iServer].iReservedSlots));
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
stock void LoadServers()
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadServers");
	
	DB.Format(Query, sizeof(Query), "SELECT * FROM `server_redirect_servers` WHERE `server_id` != %d ORDER BY `server_id`", g_srCurrentServer.iServerID);
	
	if (g_cvPrintDebug.BoolValue)
		LogMessage("[LoadServers] Query: %s", Query);
	
	DB.Query(T_OnServersReceive, Query);
}

// Clean other servers array
stock void CleanServersArray(int iStart)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- CleanServersArray | Cleaned the array from the %d index to the end", iStart);
	
	Server CleanServer;
	
	for (int iCurrentServer = iStart; iCurrentServer < MAX_SERVERS; iCurrentServer++)
		g_srOtherServers[iCurrentServer] = CleanServer;
}

// Load Category-Menu
stock void LoadCategoryMenu(int client, char[] sCategory)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadCategoryMenu");
	
	char sMenuTitle[128];
	Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MenuTitleCategory", PREFIX_NO_COLOR, sCategory);
	SelectServerMenu(client, sCategory, ServerListMenuHandler, sMenuTitle, strlen(sMenuTitle));
}

// Load Category-Menu
stock void SelectServerMenu(int client, const char[] sCategory, MenuHandler hMenuHandlerToUse, const char[] sTitle, int iTitleLength)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- SelectServerMenu");
	
	Menu mServerCategoryList = new Menu(hMenuHandlerToUse);
	
	mServerCategoryList.SetTitle(sTitle);
	
	int iNumOfPublicServers = LoadMenuServers(mServerCategoryList, client, sCategory, iTitleLength);
	
	if(iNumOfPublicServers == 0)
		CPrintToChat(client, "%t", "NoServersFound", PREFIX);
					
	mServerCategoryList.ExitButton = true;
	mServerCategoryList.ExitBackButton = true;
			
	mServerCategoryList.Display(client, MENU_TIME_FOREVER);
}

// Load Servers to choose from them
stock void SelectServerMainMenu(int client, MenuHandler mMenuHandlerToUse, const char[] sTitle, int iTitleLength, bool bAddEditAdvButton)
{
	Menu mServerList = new Menu(mMenuHandlerToUse);
	mServerList.SetTitle(sTitle);
	
	if(bAddEditAdvButton)
		mServerList.AddItem("EditAdvertisements", "Edit Advertisements\n ", CheckCommandAccess(client, "server_redirect_edit_advertisements", ADMFLAG_ROOT) ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
		
	int iNumOfPublicCategories 	= LoadMenuCategories(mServerList, client);
	int iNumOfPublicServers 	= LoadMenuServers(mServerList, client, "", iTitleLength);
	
	if(iNumOfPublicServers + iNumOfPublicCategories == 0)
		CPrintToChat(client, "%t", "NoServersFound", PREFIX);
	
	mServerList.ExitButton = true;
	
	mServerList.Display(client, MENU_TIME_FOREVER);
}

// Load servers into a menu
stock int LoadMenuServers(Menu mMenu, int client, const char[] sCategory, int iTitleLenght)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadMenuServers");
	
	int iStringSize = (460 - iTitleLenght) / 6;
	
	char[] sServerShowString = new char[iStringSize];
	
	int iNumOfPublicServers = 0;
	for (int iCurrentServer = 0; iCurrentServer < MAX_SERVERS; iCurrentServer++)
	{
		if (StrEqual(g_srOtherServers[iCurrentServer].sServerName, "", false) || !StrEqual(g_srOtherServers[iCurrentServer].sServerCategory, sCategory, false) || !ClientCanAccessToServer(client, iCurrentServer))
			continue;
		
		strcopy(sServerShowString, iStringSize, g_sMenuFormat);
		
		if (!g_srOtherServers[iCurrentServer].bShowInServerList)
			Format(sServerShowString, iStringSize, "%t", "ServerHiddenMenu", sServerShowString);
			
		if (g_srOtherServers[iCurrentServer].bServerStatus)
		{
			if (g_srOtherServers[iCurrentServer].iNumOfPlayers >= g_srOtherServers[iCurrentServer].iMaxPlayers - ((!g_srOtherServers[iCurrentServer].bHiddenSlots || CanClientUseReservedSlots(client, iCurrentServer)) ? 0 : g_srOtherServers[iCurrentServer].iReservedSlots))
				Format(sServerShowString, iStringSize, "%t", "ServerFullMenu", sServerShowString);
				
			FormatStringWithServerProperties(sServerShowString, iStringSize, iCurrentServer, client);
		}
		else
			Format(sServerShowString, iStringSize, "%t", "ServerOfflineMenu", g_srOtherServers[iCurrentServer].sServerName);
			
		
		char cServerID[3];
		IntToString(iCurrentServer, cServerID, sizeof(cServerID));
		
		mMenu.AddItem(cServerID, sServerShowString, g_srOtherServers[iCurrentServer].bServerStatus ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		iNumOfPublicServers++;
	}
	
	return iNumOfPublicServers;
}

// Get the size of just the template witout the properties.
stock int GetEmptyFormatStringSize(const char[] sFormatString, int iFormatStringLenght)
{
	// Get the full template.
	char[] sFullFormatString = new char[iFormatStringLenght];
	strcopy(sFullFormatString, iFormatStringLenght, sFormatString);
	
	// What we want to get rid of.
	char sToReplace[][] =  { "{shortname}", "{longname}", "{category}", "{map}", "{status}", "{bots}", "{ip}", "{id}", "{port}", "{current}", "{max}" };
	
	// Loop throw this and remove each string.
	for (int iCurrentStringToReplace = 0; iCurrentStringToReplace < sizeof(sToReplace); iCurrentStringToReplace++)
		ReplaceString(sFullFormatString, iFormatStringLenght, sToReplace[iCurrentStringToReplace], "");
	
	// return the lenght of the template.
	return strlen(sFullFormatString);
}

// Formats a string with server properties.
stock void FormatStringWithServerProperties(char[] sToFormat, int iStringSize, int iServerIndex, int client = -1)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- FormatStringWithServerProperties");
	
	// used to calculate how many characters we have left so we will not have oversized string.
	int iFormatSizeLeft = iStringSize - GetEmptyFormatStringSize(sToFormat, iStringSize);
	
	// for each property, the number of characters in use will be subtracted from the variable that stores the number of characters left.
	
	// SERVER ID (DB ID) - SIZE 2
	iFormatSizeLeft -= 2 * ReplaceStringWithInt(sToFormat, iStringSize, "{id}", g_srOtherServers[iServerIndex].iServerID, false);
	
	// SERVER PORT - SIZE 5
	iFormatSizeLeft -= 5 * ReplaceStringWithInt(sToFormat, iStringSize, "{port}", g_srOtherServers[iServerIndex].iServerPort, false);
	
	// CURRENT SERVER PLAYERS - SIZE 2
	iFormatSizeLeft -= 2 * ReplaceStringWithInt(sToFormat, iStringSize, "{current}", g_srOtherServers[iServerIndex].iNumOfPlayers, false);
	
	// MAX SERVER PLAYERS - SIZE 2
	iFormatSizeLeft -= 2 * ReplaceStringWithInt(sToFormat, iStringSize, "{max}", g_srOtherServers[iServerIndex].iMaxPlayers - ((!g_srOtherServers[iServerIndex].bHiddenSlots || CanClientUseReservedSlots(client, iServerIndex)) ? 0 : g_srOtherServers[iServerIndex].iReservedSlots), false);
	
	// SERVER IP - SIZE 16
	char sServerIPv4[4][4], sFullIPv4[17];
	GetIPv4FromIP32(g_srOtherServers[iServerIndex].iServerIP32, sServerIPv4);
	ImplodeStrings(sServerIPv4, 4, ".", sFullIPv4, sizeof(sFullIPv4));
	//Format(sFullIPv4, sizeof(sFullIPv4), "%s.%s.%s.%s", sFullIPv4[0], sFullIPv4[1], sFullIPv4[2], sFullIPv4[3]);
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
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty, g_srOtherServers[iServerIndex].sServerCategory, sizeof(g_srOtherServers[].sServerCategory));
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{category}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER MAP - MAX SIZE 64
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty, g_srOtherServers[iServerIndex].sServerMap, sizeof(g_srOtherServers[].sServerMap));
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{map}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER SHORT NAME - MAX SIZE <= FULL NAME
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty + iNumOfFreeCharacters, sShortServerName, sizeof(g_srOtherServers[].sServerName));
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{shortname}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER FULL NAME - MAX SIZE 245
		CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty + iNumOfFreeCharacters, g_srOtherServers[iServerIndex].sServerName, sizeof(g_srOtherServers[].sServerName));
		ReplaceString(sToFormat, iStringSize, "{longname}", sReplaceBuffer, false);
	}
}

// ReplaceString() with an Int type instead of String (char[])
stock int ReplaceStringWithInt(char[] sDest, int iDestSize, char[] sToReplace, int iValueToReplaceWith, bool bCaseSensitive = true)
{
	char sIntToString[64];
	IntToString(iValueToReplaceWith, sIntToString, sizeof(sIntToString));
	
	return ReplaceString(sDest, iDestSize, sToReplace, sIntToString, bCaseSensitive);
}

// Load Categories into a menu
stock int LoadMenuCategories(Menu mMenu, int client)
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
stock bool CategoryAlreadyExist(int iServer)
{
	for (int iCurrentServer = 0; iCurrentServer < iServer; iCurrentServer++)
	if (StrEqual(g_srOtherServers[iCurrentServer].sServerCategory, g_srOtherServers[iServer].sServerCategory, false))
		return true;
	return false;
}

// Check if the client should have access to the server
stock bool ClientCanAccessToServer(int client, int iServer)
{
	return (g_srOtherServers[iServer].bShowInServerList || CheckCommandAccess(client, "server_redirect_show_hidden_servers", ADMFLAG_ROOT));
}

// Check if the client should see reserved slots
stock bool CanClientUseReservedSlots(int client, int iServer)
{
	return (g_srOtherServers[iServer].iReservedSlots && IsValidClient(client) && CheckCommandAccess(client, "server_redirect_use_reserved_slots", ADMFLAG_ROOT));
} 