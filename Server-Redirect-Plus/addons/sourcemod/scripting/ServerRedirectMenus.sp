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
		ArrayList hUpdatedServers = new ArrayList(sizeof(Server));
		
		// We are going to loop through all the server we got
		while (SQL_FetchRow(hQuery))
		{
			Server srNewServer;
			
			srNewServer.iServerSteamAID = SQL_FetchInt(hQuery, SQL_FIELD_SERVER_STEAM_ID);
			
			if(srNewServer.IsTimedOut(hQuery))
			{
				srNewServer.DeleteFromDB();
				continue;
			}
			
			// Store everything that we get from the database 
			srNewServer.iServerIP32 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_IP);
			srNewServer.iServerPort 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_PORT);
			srNewServer.iReservedSlots 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_RESERVED_SLOTS);
			
			srNewServer.bServerStatus 	  = view_as<bool>(SQL_FetchInt(hQuery, SQL_FIELD_SERVER_STATUS));
			srNewServer.bShowInServerList = view_as<bool>(SQL_FetchInt(hQuery, SQL_FIELD_SERVER_VISIBLE));
			srNewServer.bHiddenSlots	  = view_as<bool>(SQL_FetchInt(hQuery, SQL_FIELD_SERVER_HIDDEN_SLOTS));
			srNewServer.bIncludeBots 	  = view_as<bool>(SQL_FetchInt(hQuery, SQL_FIELD_SERVER_INCLUD_BOTS));
			
			SQL_FetchString(hQuery, SQL_FIELD_SERVER_NAME	 , srNewServer.sServerName	  , sizeof(srNewServer.sServerName)		);
			SQL_FetchString(hQuery, SQL_FIELD_SERVER_CATEGORY, srNewServer.sServerCategory, sizeof(srNewServer.sServerCategory)	);
			
			// if the server is offline we don't want to load real-time data because it's not real-time (outdated),
			// And we don't want to advertise Map-Changes / Player-Range Advertisements.
			if (srNewServer.bServerStatus)
			{
				srNewServer.iNumOfPlayers 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_PLAYERS);
				srNewServer.iMaxPlayers 	= SQL_FetchInt(hQuery, SQL_FIELD_SERVER_MAX_PLAYERS);
				
				SQL_FetchString(hQuery, SQL_FIELD_SERVER_MAP, srNewServer.sServerMap, sizeof(srNewServer.sServerMap));
				
				if(g_bAdvertisementsAreEnabled && !bFirstLoad)
				{
					int iOldServerIndex = GetServerIndexByServerID(srNewServer.iServerSteamAID);
					
					if(iOldServerIndex != -1)
					{
						Server srOldServer;
						srOldServer = GetServerByIndex(iOldServerIndex);
						
						if (!StrEqual(srOldServer.sServerMap, srNewServer.sServerMap))
							PostAdvertisement(srNewServer.iServerSteamAID, ADVERTISEMENT_MAP);
					}
					
					int iServerAdvertisement = FindAdvertisement(srNewServer.iServerSteamAID, ADVERTISEMENT_PLAYERS_RANGE);
					Advertisement advServerAdvertisement;
					
					if (iServerAdvertisement != -1)
					{
						advServerAdvertisement = GetAdvertisementByIndex(iServerAdvertisement);
						
						if(advServerAdvertisement.iPlayersRange[0] <= srNewServer.iNumOfPlayers <= advServerAdvertisement.iPlayersRange[1])
							PostAdvertisement(srNewServer.iServerSteamAID, ADVERTISEMENT_PLAYERS_RANGE);
					}
				}
			}
			
			hUpdatedServers.PushArray(srNewServer, sizeof(srNewServer));
			
			if (g_cvPrintDebug.BoolValue)
				LogMessage("[T_OnServersReceive -> LOOP -> IF] Server Steam ID %d (Status: %b | Show: %b): \nName: %s, Category: %s, Map: %s, IP32: %d, Port: %d, Number of players: %d, Max players: %d",
					srNewServer.iServerSteamAID,
					srNewServer.bServerStatus,
					srNewServer.bShowInServerList,
					srNewServer.sServerName,
					srNewServer.sServerCategory,
					srNewServer.sServerMap,
					srNewServer.iServerIP32,
					srNewServer.iServerPort,
					srNewServer.iNumOfPlayers,
					srNewServer.iMaxPlayers
				);
		}
		
		// Reload Advertisements if a server got deleted.
		if(!bFirstLoad && g_bAdvertisementsAreEnabled && g_hOtherServers.Length != hUpdatedServers.Length)
			LoadAdvertisements();
		else // Create Advertisements Table on First-Load.
			CreateAdvertisementsTable();
		
		if(g_hOtherServers)
			delete g_hOtherServers;
		
		g_hOtherServers = hUpdatedServers;
		
		if (g_cvPrintDebug.BoolValue && !g_hOtherServers.Length)
			LogError("No servers found in DB.");
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
		
	Server srServer;
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
			else													// If we ended up here the client clicked on a server, let's prepare the server menu.
			{
				// Get the Server-ID from the item info we got earlier.
				char cServerID[4];
				strcopy(cServerID, sizeof(cServerID), sMenuItemInfo);
				
				// Save it as int, we will use that also.
				int iServer = StringToInt(sMenuItemInfo);
				srServer = GetServerByIndex(iServer);
				
				// Get the server IP as 'xxx.xxx.xxx.xxx' from IP32
				char ServerIP[4][4];
				GetIPv4FromIP32(srServer.iServerIP32, ServerIP);
				
				// Now we finally create the menu, also format the title.
				Menu mServerInfo = new Menu(ServerInfoMenuHandler);
				mServerInfo.SetTitle("%s [%s.%s.%s.%s:%d]\n ", srServer.sServerName, ServerIP[0], ServerIP[1], ServerIP[2], ServerIP[3], srServer.iServerPort);
				
				bool bCanUseReservedSlots = CanClientUseReservedSlots(client, iServer);
				int iMaxPlayerWithReserved = srServer.iMaxPlayers - ((!srServer.bHiddenSlots || bCanUseReservedSlots) ? 0 : srServer.iReservedSlots);
				
				// Is the server full?
				bool bIsServerFull = srServer.iNumOfPlayers >= iMaxPlayerWithReserved;
				
				char sEditBuffer[128];
				
				// Add 'Number of player'.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "NumberOfPlayersMenu", srServer.iNumOfPlayers, iMaxPlayerWithReserved, bIsServerFull ? "ServerFullMenu" : "EmptyText");
				
				if(srServer.iReservedSlots && (!srServer.bHiddenSlots || bCanUseReservedSlots))
					Format(sEditBuffer, sizeof(sEditBuffer), "%s %t", sEditBuffer, "ServerReservedSlots", srServer.iReservedSlots);
					
				mServerInfo.AddItem("", sEditBuffer, srServer.bServerStatus ? ITEMDRAW_DISABLED : ITEMDRAW_IGNORE);
				
				// Add 'Map'.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t\n ", "ServerMapMenu", srServer.sServerMap);
				mServerInfo.AddItem("", sEditBuffer, srServer.bServerStatus ? ITEMDRAW_DISABLED : ITEMDRAW_IGNORE);
				
				// Add clickable option to print the info.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "PrintInfoMenu");
				mServerInfo.AddItem("", sEditBuffer);
				
				// Add clickable option to join the server.
				Format(sEditBuffer, sizeof(sEditBuffer), "%t", "JoinServerMenu");
				
				if(!srServer.bServerStatus)
					Format(sEditBuffer, sizeof(sEditBuffer), "%s %t", sEditBuffer, "ServerOfflineMenu");
				
				mServerInfo.AddItem(cServerID, sEditBuffer, srServer.bServerStatus && (!bIsServerFull || CheckCommandAccess(client, "server_redirect_join_full_bypass", ADMFLAG_ROOT)) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
				
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
			
			if (Clicked == MenuCancel_Exit && !StrEqual(sFirstMenuItemInfoBuffer, "EditAdvertisements"))
			{
				srServer = GetServerByIndex(StringToInt(sFirstMenuItemInfoBuffer));
				
				if(!StrEqual(srServer.sServerCategory, ""))
					Command_ServerList(client, 0);
			}
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
	
	Server srServer;
	srServer = GetServerByIndex(iServer);
	
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
					GetIPv4FromIP32(srServer.iServerIP32, ServerIP);
					
					CPrintToChat(client, "%t", "ServerInfoHeadline"	, PREFIX, srServer.sServerName);
					CPrintToChat(client, "%t", "ServerInfoIP"		, PREFIX, ServerIP[0], ServerIP[1], ServerIP[2], ServerIP[3], srServer.iServerPort);
					
					if(srServer.bServerStatus)
					{
						CPrintToChat(client, "%t", "ServerInfoMap"		, PREFIX, srServer.sServerMap);
						CPrintToChat(client, "%t", "ServerInfoPlayers"	, PREFIX, srServer.iNumOfPlayers, srServer.iMaxPlayers - ((!srServer.bHiddenSlots || CanClientUseReservedSlots(client, iServer)) ? 0 : srServer.iReservedSlots));
					}
					
				}
				// Clicked on the redirect / join button.
				case 3:
				{
					RedirectClientOnServer(client, srServer.iServerIP32, srServer.iServerPort);
				}
			}
		}
		case MenuAction_Cancel:
		{
			// Exit back to the menu (if was in a category - to the category, else - to the main menu)
			if (!StrEqual(srServer.sServerCategory, "", false))
				LoadCategoryMenu(client, srServer.sServerCategory);
			else
				Command_ServerList(client, 0);
		}
		case MenuAction_End:
		{
			delete ServerInfoMenu;
		}
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
	Server srServer;
	
	int iNumOfPublicServers = 0;
	for (int iCurrentServer = 0; iCurrentServer < g_hOtherServers.Length; iCurrentServer++)
	{
		srServer = GetServerByIndex(iCurrentServer);
		
		if (StrEqual(srServer.sServerName, "", false) || !StrEqual(srServer.sServerCategory, sCategory, false) || !ClientCanAccessToServer(client, iCurrentServer))
			continue;
		
		strcopy(sServerShowString, iStringSize, sMenuFormat);
		
		if (!srServer.bShowInServerList)
			Format(sServerShowString, iStringSize, "%s %t", sServerShowString, "ServerHiddenMenu");
		
		if (srServer.bServerStatus)
		{
			if (srServer.iNumOfPlayers >= srServer.iMaxPlayers - ((!srServer.bHiddenSlots || CanClientUseReservedSlots(client, iCurrentServer)) ? 0 : srServer.iReservedSlots))
				Format(sServerShowString, iStringSize, "%s %t", sServerShowString, "ServerFullMenu");
				
			FormatStringWithServerProperties(sServerShowString, iStringSize + 1, iCurrentServer, client);
		}
		else
			Format(sServerShowString, iStringSize, "%s %t", srServer.sServerName, "ServerOfflineMenu");
		
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
	
	Server srServer;
	srServer = GetServerByIndex(iServerIndex);
	
	// used to calculate how many characters we have left so we will not have oversized string.
	int iFormatSizeLeft = iStringSize - GetEmptyFormatStringSize(sToFormat, iStringSize);
	
	// for each property, the number of characters in use will be subtracted from the variable that stores the number of characters left.
	
	// SERVER ID (DB ID)
	iFormatSizeLeft -= ReplaceStringWithInt(sToFormat, iStringSize, "{id}", srServer.iServerSteamAID, false);
	
	// SERVER PORT
	iFormatSizeLeft -= ReplaceStringWithInt(sToFormat, iStringSize, "{port}", srServer.iServerPort, false);
	
	// CURRENT SERVER PLAYERS
	iFormatSizeLeft -= ReplaceStringWithInt(sToFormat, iStringSize, "{current}", srServer.iNumOfPlayers, false);
	
	// MAX SERVER PLAYERS 
	iFormatSizeLeft -= ReplaceStringWithInt(sToFormat, iStringSize, "{max}", srServer.iMaxPlayers - ((!srServer.bHiddenSlots || CanClientUseReservedSlots(client, iServerIndex)) ? 0 : srServer.iReservedSlots), false);
	
	// SERVER IP - SIZE 16
	char sServerIPv4[4][4], sFullIPv4[17];
	GetIPv4FromIP32(srServer.iServerIP32, sServerIPv4);
	ImplodeStrings(sServerIPv4, 4, ".", sFullIPv4, sizeof(sFullIPv4));
	iFormatSizeLeft -= 16 * ReplaceString(sToFormat, iStringSize, "{ip}", sFullIPv4, false);
	
	// SERVER STATUS - SIZE 7
	iFormatSizeLeft -= 7 * ReplaceString(sToFormat, iStringSize, "{status}", srServer.bServerStatus ? "ONLINE" : "OFFLINE", false);
	
	// BOTS INCLUDED - SIZE 14
	iFormatSizeLeft -= 14 * ReplaceString(sToFormat, iStringSize, "{bots}", srServer.bIncludeBots ? "Players & Bots" : "Real Players", false);
	
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
		strcopy(sShortServerName, sizeof(sShortServerName), srServer.sServerName);
		
		// Remove the Prefix string
		if (!StrEqual(g_sPrefixRemover, "", false))
		{
			if (g_cvPrintDebug.BoolValue)
				LogMessage("Removing '%s' from '%s'", g_sPrefixRemover, sShortServerName);
			
			ReplaceString(sShortServerName, sizeof(sShortServerName), g_sPrefixRemover, "", true);
		}
		
		// SERVER CATEGORY - MAX SIZE 64
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty, srServer.sServerCategory);
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{category}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER MAP - MAX SIZE 64
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty, srServer.sServerMap);
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{map}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER SHORT NAME - MAX SIZE <= FULL NAME
		iClaculateBuffer = CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty + (iNumOfFreeCharacters > 0 ? iNumOfFreeCharacters : 0), sShortServerName);
		iClaculateBuffer *= ReplaceString(sToFormat, iStringSize, "{shortname}", sReplaceBuffer, false);
		iNumOfFreeCharacters += iClaculateBuffer;
		
		// SERVER FULL NAME - MAX SIZE 245
		CopyStringWithDots(sReplaceBuffer, iLenghtForEachProperty + (iNumOfFreeCharacters > 0 ? iNumOfFreeCharacters : 0), srServer.sServerName);
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
	Server srServer;
	
	for (int iCurrentServer = 0; iCurrentServer < g_hAdvertisements.Length; iCurrentServer++)
	{
		srServer = GetServerByIndex(iCurrentServer);
		
		if (StrEqual(srServer.sServerCategory, "", false) || CategoryAlreadyExist(iCurrentServer) || !ClientCanAccessToServer(client, iCurrentServer))
			continue;
		
		char sBuffer[MAX_CATEGORY_NAME_LENGHT];
		Format(sBuffer, sizeof(sBuffer), "[C] %s", srServer.sServerCategory);
		
		mMenu.AddItem(sBuffer, sBuffer);
		iNumOfPublicCategories++;
	}
	
	return iNumOfPublicCategories;
}

// Check if Category already exists
bool CategoryAlreadyExist(int iServer)
{
	Server srServerToStop, sCurrentServer;
	srServerToStop = GetServerByIndex(iServer);
	
	for (int iCurrentServer = 0; iCurrentServer < iServer; iCurrentServer++)
	{
		sCurrentServer = GetServerByIndex(iCurrentServer);
		if (StrEqual(sCurrentServer.sServerCategory, srServerToStop.sServerCategory, false))
			return true;
	}
	
	return false;
}

// Check if the client should have access to the server
bool ClientCanAccessToServer(int client, int iServer)
{
	static Server srServerToCheck;
	srServerToCheck = GetServerByIndex(iServer);
	
	return (srServerToCheck.bShowInServerList || CheckCommandAccess(client, "server_redirect_show_hidden_servers", ADMFLAG_ROOT));
}

// Check if the client should see reserved slots
bool CanClientUseReservedSlots(int client, int iServer)
{
	static Server srServerToCheck;
	srServerToCheck = GetServerByIndex(iServer);
	
	return (srServerToCheck.iReservedSlots && CheckCommandAccess(client, "server_redirect_use_reserved_slots", ADMFLAG_ROOT));
} 