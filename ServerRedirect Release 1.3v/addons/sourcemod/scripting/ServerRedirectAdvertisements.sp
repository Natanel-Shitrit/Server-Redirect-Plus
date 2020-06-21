public Plugin myinfo = 
{
	name = "[Server-List] Advertisements", 
	author = "Natanel 'LuqS'", 
	description = "Advertisements of 'Server-Redirect+', offer variety of options to advertise other servers.", 
	version = "1.3", 
	url = "https://steamcommunity.com/id/luqsgood | Discord: LuqS#6505"
};

//====================[ EVENTS ]=====================//
public Action OnClientSayCommand(int client, const char[] command, const char[] args)
{
	if(g_iUpdateAdvProprietary[client] != UPDATE_NOTHING)
	{
		if(!StrEqual(args, "-1"))
		{
			switch(g_iUpdateAdvProprietary[client])
			{
				case UPDATE_LOOP_TIME:
				{
					int iTime = StringToInt(args);
					
					if(iTime > 0)
						g_advToEdit.iRepeatTime = iTime;
				}
				case UPDATE_COOLDOWN_TIME:
				{
					int iTime = StringToInt(args);
					
					if(iTime > 0)
						g_advToEdit.iCoolDownTime = iTime;
				}
					
				case UPDATE_PLAYER_RANGE:
				{
					if(StrContains(args, "|") == -1 || strlen(args) > 6)
					{
						PrintToChat(client, "%s \x02Invalid\x01 string for \x04Player-Range\x01.", PREFIX);
						PrintToChat(client, "%s \x04Valid\x01 string template: \x02{min}|{max}\x01", PREFIX);
						PrintToChat(client, "%s \x04Example\x01:\x02 10|15 \x01(10 is \x04min\x01, 15 is \x02max\x01)", PREFIX);
						return Plugin_Handled;
					}
					g_advToEdit.iPlayersRange = GetPlayerRangeFromString(args, g_srOtherServers[GetServerIndexByServerID(g_advToEdit.iServerIDToAdvertise)].iMaxPlayers);
					PrintToChat(client, "%s \x04Successfully\x01 updated \x04Player-Range\x01", PREFIX);
				}
				case UPDATE_ADV_MESSAGE:
				{
					if(String_StartsWith(args, "<ADD>"))
						StrCat(g_advToEdit.sMessageContent, sizeof(g_advToEdit.sMessageContent), args[5]);
					else
						strcopy(g_advToEdit.sMessageContent, sizeof(g_advToEdit.sMessageContent), args);
				}
			}
		}
		
		g_iUpdateAdvProprietary[client] = UPDATE_NOTHING;
		EditAdvertisementPropertiesMenu(client);
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

// Timer to advertise
public Action Timer_Loop(Handle hTimer)
{
	++g_iTimerCounter;
	
	for (int iCurrentAdvertisement = 0; iCurrentAdvertisement < MAX_ADVERTISEMENTS; iCurrentAdvertisement++)
	{
		int iAdvertisementRepeatTime = g_advAdvertisements[iCurrentAdvertisement].iRepeatTime;
		
		if(iAdvertisementRepeatTime && g_iTimerCounter % iAdvertisementRepeatTime == 0)
			PostAdvertisement(g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise, ADVERTISEMENT_LOOP, iCurrentAdvertisement);
	}
	
	return Plugin_Continue;
}

//================[ MENUS & HANDLES ]================//
// sm_editsradv menu
public Action Command_EditServerRedirectAdvertisements(int client, int args)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Command_EditServerRedirectAdvertisements | Fired by %N (%d)", client, client);
	
	Menu mEditAdvertisements = new Menu(EditAdvertisementsMenuHandler);
	//mEditAdvertisements.SetTitle("%t", "MenuTitleEditAdvertisements", PREFIX_NO_COLOR);
	mEditAdvertisements.SetTitle("%s Edit Advertisements\n ", PREFIX_NO_COLOR);
	
	//mEditAdvertisements.SetTitle("%t", "MenuTitleAddAdvertisement", PREFIX_NO_COLOR);
	mEditAdvertisements.AddItem("", "Add Advertisement\n ");
	
	if(LoadMenuAdvertisements(mEditAdvertisements) == 0)
		mEditAdvertisements.AddItem("", "No Advertisements was found!");
	
	mEditAdvertisements.ExitButton = true;
	mEditAdvertisements.Display(client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int EditAdvertisementsMenuHandler(Menu EditAdvertisementsMenu, MenuAction action, int client, int Clicked)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- EditAdvertisementsMenuHandler");
	
	switch(action)
	{
		case MenuAction_Select:
		{
			if(Clicked == 0)
			{
				g_advToEdit.iAdvID = -1;
				EditAdvertisementPropertiesMenu(client);
			}
			else
			{
				char sAdvertisementID[3];
				EditAdvertisementsMenu.GetItem(Clicked, sAdvertisementID, sizeof(sAdvertisementID));
				
				if(!StrEqual(sAdvertisementID, ""))
				{
					LoadAdvToEdit(StringToInt(sAdvertisementID));
					EditAdvertisementPropertiesMenu(client);
				}
			}
		}
		case MenuAction_End:
			delete EditAdvertisementsMenu;
	}
}

// Edit Adv menu
stock void EditAdvertisementPropertiesMenu(int client)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- EditAdvertisementPropertiesMenu");
	
	char sBuffer[MAX_BUFFER_SIZE];
	
	Menu mAddAdvertisement = new Menu(AddAdvertisementMenuHandler);
	//mAddAdvertisement.SetTitle("%t", "MenuAddAdvTitle", PREFIX_NO_COLOR);
	mAddAdvertisement.SetTitle("%s %s advertisement\n ", PREFIX_NO_COLOR, g_advToEdit.iAdvID == -1 ? "Add" : "Edit");
	
	//Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvServerToAdv",  g_advToEdit.iServerIDToAdvertise);
	Format(sBuffer, sizeof(sBuffer), "Server to advertise: %d", g_advToEdit.iServerIDToAdvertise); 
	mAddAdvertisement.AddItem("AdvServerID", sBuffer);// 0
	
	//Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvMode", g_advToEdit.iRepeatTime >= 0 ? "LOOP" : g_advToEdit.iRepeatTime == -1 ? "MAP" : "PLAYERS");
	Format(sBuffer, sizeof(sBuffer), "Advertisement mode: %s", g_advToEdit.iRepeatTime >= 0 ? "LOOP" : g_advToEdit.iRepeatTime == -1 ? "MAP" : "PLAYERS");
	mAddAdvertisement.AddItem("AdvMode", sBuffer);// 1
	
	//Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvLoopTime", g_advToEdit.iRepeatTime);
	Format(sBuffer, sizeof(sBuffer), "Advertisement loop time: %d", g_advToEdit.iRepeatTime);
	mAddAdvertisement.AddItem("AdvLoopTime", sBuffer, g_advToEdit.iRepeatTime >= 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE); // 2
	
	//Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvCooldownTime", g_advToEdit.iCoolDownTime);
	Format(sBuffer, sizeof(sBuffer), "Advertisement cooldown time: %d", g_advToEdit.iCoolDownTime);
	mAddAdvertisement.AddItem("AdvLoopTime", sBuffer, g_advToEdit.iRepeatTime < 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE); // 3
	
	//Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvPlayerRange", g_advToEdit.iPlayersRange[0], g_advToEdit.iPlayersRange[1]);
	Format(sBuffer, sizeof(sBuffer), "Advertisement player range: %d | %d", g_advToEdit.iPlayersRange[0], g_advToEdit.iPlayersRange[1]);
	mAddAdvertisement.AddItem("AdvPlayerRange", sBuffer, g_advToEdit.iRepeatTime == -2 ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE); // 4
	
	char sAdvMessage[32];
	CopyStringWithDots(sAdvMessage, sizeof(sAdvMessage), g_advToEdit.sMessageContent, sizeof(g_advToEdit.sMessageContent));
	
	//Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvMessage", sAdvMessage);
	Format(sBuffer, sizeof(sBuffer), "Advertisement message: %s", sAdvMessage);
	mAddAdvertisement.AddItem("AdvPlayerRange", sBuffer); // 5
	
	char sAdvID[4];
	IntToString(g_advToEdit.iAdvID, sAdvID, sizeof(sAdvID));
	//mAddAdvertisement.AddItem(sAdvID, "%t", "MenuAddAdvAddAdv");
	mAddAdvertisement.AddItem(sAdvID, g_advToEdit.iAdvID == -1 ? "Add Advertisement" : "Edit Advertisement"); // 6
	
	//mAddAdvertisement.AddItem(sAdvID, "%t", "MenuAddAdvAddAdv");
	mAddAdvertisement.AddItem(sAdvID, g_advToEdit.iAdvID == -1 ? "Reset Advertisement" : "Delete Advertisement"); // 7
	
	mAddAdvertisement.ExitButton = true;
	
	mAddAdvertisement.Display(client, MENU_TIME_FOREVER);
	
}

public int AddAdvertisementMenuHandler(Menu AddAdvertisementMenu, MenuAction action, int client, int Clicked)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- AddAdvertisementMenuHandler");
	
	switch(action)
	{
		case MenuAction_Select:
		{
			char sAdvID[4];
			AddAdvertisementMenu.GetItem(7, sAdvID, sizeof(sAdvID));
			int iAdvID = StringToInt(sAdvID);
			
			switch(Clicked)
			{
				case 0:
					SelectServerToAdvMenu(client);
				case 1:
				{
					g_advToEdit.iRepeatTime = g_advToEdit.iRepeatTime >= 0 ? -1 : g_advToEdit.iRepeatTime == -1 ? -2 : 0;
					EditAdvertisementPropertiesMenu(client);
				}
				case 2:
					g_iUpdateAdvProprietary[client] = UPDATE_LOOP_TIME; 	// TODO: update loop time
				case 3:
					g_iUpdateAdvProprietary[client] = UPDATE_COOLDOWN_TIME; // TODO: update cooldown
				case 4:
					g_iUpdateAdvProprietary[client] = UPDATE_PLAYER_RANGE; 	// TODO: update player range
				case 5:
				{
					if(!StrEqual(g_advToEdit.sMessageContent, ""))
						PrintToChat(client, "%s \x02Editing\x01 Message: %s", PREFIX, g_advToEdit.sMessageContent);
						
					g_iUpdateAdvProprietary[client] = UPDATE_ADV_MESSAGE; 	// TODO: update adv message
				}
				case 6:
				{
					iAdvID == -1 ? AddAdvertisementToDB() : UpdateAdvertisementDB(iAdvID);		// TODO: Add / Edit adv
					
					ResetAdvToEdit();
				}
				case 7:
				{
					iAdvID == -1 ? ResetAdvToEdit() : DeleteAdvertisementDB(iAdvID);
				}
			}
			
			if(1 < Clicked < 6)
			{
				PrintToChat(client, "%s \x04Entered edit mode\x01, please enter the \x02value\x01 in chat!", PREFIX);
				PrintToChat(client, "%s To \x02abort\x01 type \x04-1\x01.", PREFIX);
			}
		}
		case MenuAction_Cancel:
			Command_EditServerRedirectAdvertisements(client, 0);
		case MenuAction_End:
			delete AddAdvertisementMenu;
	}
}

// Load Servers to choose from them
stock void SelectServerToAdvMenu(int client)
{
	Menu mSelectServerToAdv = new Menu(SelectServerToAdvMenuHandler);
	//mServerList.SetTitle("%t", "MenuTitleSelectServerToAdv", PREFIX_NO_COLOR);
	mSelectServerToAdv.SetTitle("%s Select Server to Advertise:\n ", PREFIX_NO_COLOR);
	
	int iNumOfPublicCategories 	= LoadMenuCategories(mSelectServerToAdv, client);
	int iNumOfPublicServers 	= LoadMenuServers(mSelectServerToAdv, client, "");
	
	if(iNumOfPublicServers + iNumOfPublicCategories == 0)
		CPrintToChat(client, "%t", "NoServersFound", PREFIX);
	
	mSelectServerToAdv.ExitButton = true;
	
	mSelectServerToAdv.Display(client, MENU_TIME_FOREVER);
}

public int SelectServerToAdvMenuHandler(Menu SelectServerToAdv, MenuAction action, int client, int Clicked)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- SelectServerToAdvMenuHandler");
	
	switch(action)
	{
		case MenuAction_Select:
		{
			char sBuffer[MAX_BUFFER_SIZE];
			SelectServerToAdv.GetItem(Clicked, sBuffer, sizeof(sBuffer));
			
			if(StrContains(sBuffer, "[C]") != -1)
			{
				SelectServerToAdvCategoryMenu(client, sBuffer[4]);
			}
			else
			{
				g_advToEdit.iServerIDToAdvertise = g_srOtherServers[StringToInt(sBuffer)].iServerID;
				EditAdvertisementPropertiesMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete SelectServerToAdv;
		}
	}
}

// Load Category-Menu
stock void SelectServerToAdvCategoryMenu(int client, char[] sCategory)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- SelectServerToAdvCategoryMenu");
	
	Menu mServerCategoryList = new Menu(SelectServerToAdvMenuHandler);
	//mServerCategoryList.SetTitle("%t", "MenuTitleSelectFromCategoryToAdv", PREFIX_NO_COLOR, sCategory);
	mServerCategoryList.SetTitle("%s Select Server from %s", PREFIX_NO_COLOR, sCategory);
	
	int iNumOfPublicServers = LoadMenuServers(mServerCategoryList, client, sCategory);
	
	if(iNumOfPublicServers == 0)
		CPrintToChat(client, "%t", "NoServersFound", PREFIX);
					
	mServerCategoryList.ExitButton = true;
	mServerCategoryList.ExitBackButton = true;
			
	mServerCategoryList.Display(client, MENU_TIME_FOREVER);
}

stock int LoadMenuAdvertisements(Menu hMenuToAdd)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadMenuAdvertisements");
	
	int iCurrentAdvertisement;
	char sBuffer[MAX_BUFFER_SIZE];
	
	for (iCurrentAdvertisement = 0; iCurrentAdvertisement < MAX_ADVERTISEMENTS; iCurrentAdvertisement++) 
	{
		if(g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise != 0)
		{
			int iServerIndex = GetServerIndexByServerID(g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise);
			
			char sServerName[32], sAdvMessage[32];
			CopyStringWithDots(sServerName, sizeof(sServerName), g_srOtherServers[iServerIndex].sServerName, sizeof(g_srOtherServers[].sServerName));
			CopyStringWithDots(sAdvMessage, sizeof(sAdvMessage), g_advAdvertisements[iCurrentAdvertisement].sMessageContent, sizeof(g_advAdvertisements[].sMessageContent));
			
			// 6 Template, 3 ServerID, TYPE - 7, 32 Strings == 80
			Format(sBuffer, sizeof(sBuffer), "%s (ID %d - %s) | %s",
			sServerName,
			g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise,
			g_advAdvertisements[iCurrentAdvertisement].iRepeatTime > 0 ? "LOOP" : g_advAdvertisements[iCurrentAdvertisement].iRepeatTime == -1 ? "MAP" : "PLAYERS",
			sAdvMessage
			);
			
			char sAdvID[5];
			IntToString(iCurrentAdvertisement, sAdvID, sizeof(sAdvID));
			
			hMenuToAdd.AddItem(sAdvID, sBuffer);
		}
	}
	
	return iCurrentAdvertisement;
}

//======================[ DB ]=======================//
// Updating the advertisement in the DB and refreshing the 
stock void UpdateAdvertisementDB(int iAdvertisement)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- UpdateAdvertisementDB | iAdvertisement = %d", iAdvertisement);
	
	char sPlayersRange[6];
	Format(sPlayersRange, sizeof(sPlayersRange), "%d|%d", g_advToEdit.iPlayersRange[0], g_advToEdit.iPlayersRange[1]);
	
	DB.Format(Query, sizeof(Query), "UPDATE `server_redirect_advertisements` SET `server_id_to_adv` = %d, `adv_repeat_time` = %d, `adv_cooldown_time` = %d, `adv_players_range` = '%s', `adv_message` = '%s' WHERE `id` = %d",
	g_advToEdit.iServerIDToAdvertise,
	g_advToEdit.iRepeatTime,
	g_advToEdit.iCoolDownTime,
	sPlayersRange,
	g_advToEdit.sMessageContent,
	g_advToEdit.iAdvID
	);
	
	
	DB.Query(T_UpdateAdvertisementQuery, Query, false);
}

stock void DeleteAdvertisementDB(int iAdvertisement)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- DeleteAdvertisementDB | iAdvertisement = %d", iAdvertisement);	
	
	Format(Query, sizeof(Query), "DELETE FROM `server_redirect_advertisements` WHERE `id` = %d", iAdvertisement);	
	
	if(g_cvPrintDebug.BoolValue)
		LogMessage(Query);
	
	DB.Query(T_UpdateAdvertisementQuery, Query, false);
}

stock void AddAdvertisementToDB()
{
	char sPlayersRange[6];
	Format(sPlayersRange, sizeof(sPlayersRange), "%d|%d", g_advToEdit.iPlayersRange[0], g_advToEdit.iPlayersRange[1]);
	
	DB.Format(Query, sizeof(Query), "INSERT INTO `server_redirect_advertisements`(`server_id`, `server_id_to_adv`, `adv_repeat_time`, `adv_cooldown_time`, `adv_players_range`, `adv_message`) VALUES (%d, %d, %d, %d, '%s', '%s')",
	g_srCurrentServer.iServerID,
	g_advToEdit.iServerIDToAdvertise,
	g_advToEdit.iRepeatTime,
	g_advToEdit.iCoolDownTime,
	sPlayersRange,
	g_advToEdit.sMessageContent
	);
	
	if(g_cvPrintDebug.BoolValue)
		LogMessage(Query);
	
	DB.Query(T_UpdateAdvertisementQuery, Query, false);
}

public void T_UpdateAdvertisementQuery(Handle owner, Handle hQuery, const char[] sError, any bStartTimer)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_UpdateAdvertisementQuery");
	
	if (hQuery != INVALID_HANDLE)
	{
		LoadAdvertisements(bStartTimer);
	}
	else
		LogError("Error in T_FakeFastQuery: %s", sError);
}

stock void CreateAdvertisementsTable()
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- CreateAdvertisementsTable");
	
	DB.Query(T_OnAdvertisementsTableCreated, "CREATE TABLE IF NOT EXISTS `server_redirect_advertisements`(`id` INT NOT NULL AUTO_INCREMENT, `server_id` INT(11) NOT NULL, `server_id_to_adv` INT(11) NOT NULL, `adv_repeat_time` INT NOT NULL, `adv_cooldown_time` INT NOT NULL, `adv_players_range` VARCHAR(6) NOT NULL, `adv_message` VARCHAR(512) NOT NULL, PRIMARY KEY (`id`))", true, DBPrio_High);
}

public void T_OnAdvertisementsTableCreated(Handle owner, Handle hQuery, const char[] sError, any bStartTimer)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnAdvertisementsTableCreated");
	
	if (hQuery != INVALID_HANDLE)
		LoadAdvertisements(bStartTimer);
	else
		LogError("Error in T_OnAdvertisementsTableCreated: %s", sError);
}

stock void LoadAdvertisements(bool bStartTimer)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadAdvertisements");
	
	DB.Format(Query, sizeof(Query), "SELECT * FROM `server_redirect_advertisements` WHERE `server_id` = %d", g_srCurrentServer.iServerID);
	DB.Query(T_OnAdvertisementsRecive, Query, bStartTimer);
}

public void T_OnAdvertisementsRecive(Handle owner, Handle hQuery, const char[] sError, any bStartTimer)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnAdvertisementsRecive");
		
	if(hQuery != INVALID_HANDLE)
	{
		int iCurrentAdvertisement;
		
		for (iCurrentAdvertisement = 0; iCurrentAdvertisement < MAX_ADVERTISEMENTS && SQL_FetchRow(hQuery); iCurrentAdvertisement++) 
		{
			g_advAdvertisements[iCurrentAdvertisement].iAdvID					= SQL_FetchIntByName(hQuery, "id"				);
			g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise 	= SQL_FetchIntByName(hQuery, "server_id_to_adv"	);
			g_advAdvertisements[iCurrentAdvertisement].iRepeatTime 				= SQL_FetchIntByName(hQuery, "adv_repeat_time"	);
			g_advAdvertisements[iCurrentAdvertisement].iCoolDownTime 			= SQL_FetchIntByName(hQuery, "adv_cooldown_time");
			int iServerIndex = GetServerIndexByServerID(g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise);
			
			char sRangeString[6];
			SQL_FetchStringByName(hQuery, "adv_players_range", sRangeString, sizeof(sRangeString));
			
			g_advAdvertisements[iCurrentAdvertisement].iPlayersRange = GetPlayerRangeFromString(sRangeString, g_srOtherServers[iServerIndex].iMaxPlayers); 
			
			SQL_FetchStringByName(hQuery, "adv_message", g_advAdvertisements[iCurrentAdvertisement].sMessageContent, sizeof(g_advAdvertisements[].sMessageContent));
			
			if(g_cvPrintDebug.BoolValue)
				LogMessage("[T_OnAdvertisementsRecive -> LOOP] Advertisement %d (Index: %d): iServerIDToAdvertise - %d, iRepeatTime - %d, iCoolDownTime - %d, sMessageContent - %s",
				g_advAdvertisements[iCurrentAdvertisement].iAdvID,
				iCurrentAdvertisement,
				g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise,
				g_advAdvertisements[iCurrentAdvertisement].iRepeatTime,
				g_advAdvertisements[iCurrentAdvertisement].iCoolDownTime,
				g_advAdvertisements[iCurrentAdvertisement].sMessageContent
				);
			
		}
		
		if(!iCurrentAdvertisement)
			LogError("No Advertisements found in DB.");
		else
		{
			ClearAdvertisements(iCurrentAdvertisement);
			
			if(bStartTimer)
				CreateTimer(1.0, Timer_Loop, _, TIMER_REPEAT);
		}
			
	}
	else
		LogError("Error: %s", sError);
}

//===================[ HELPING ]=====================//
// Checking and posting an advertisement if it should be posted.
stock void PostAdvertisement(int iServerID, int iAdvertisementMode = ADVERTISEMENT_LOOP, int iAdvertisementIndex = -1)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- PostAdvertisement | int iServerID = %d, int iAdvertisementMode = %d, int iAdvertisementIndex = %d", iServerID, iAdvertisementMode, iAdvertisementIndex);
	
	if(iAdvertisementIndex == -1)
		iAdvertisementIndex = FindAdvertisement(iServerID, iAdvertisementMode);
	
	if(iAdvertisementIndex != -1)
	{
		char sMessageContent[512];
		strcopy(sMessageContent, sizeof(sMessageContent), g_advAdvertisements[iAdvertisementIndex].sMessageContent);
		
		// Get Server index.
		int iServerIndex = GetServerIndexByServerID(iServerID);
		
		// Skip if server index isn't found.
		if(iServerIndex == -1)
		{
			LogError("Invalid Server index for ServerID = %d, not posting advertisement.", iServerIndex);
			return;
		}
		
		// Skip if Advertisements are disabled
		if(!g_bEnableAdvertisements)
		{
			if(g_cvPrintDebug.BoolValue)
				LogMessage("Advertisements are disabled, change 'PrefixRemover' to '1' in the plugin cfg to enable advertisements!");
			return;
		}
		
		// Skip if the server is down.
		if(!g_bAdvertiseOfflineServers && !g_srOtherServers[iServerIndex].bServerStatus)
		{
			if(g_cvPrintDebug.BoolValue)
				LogMessage("Not advertising because server is offline, change 'AdvertiseOfflineServers' to '1' in the plugin cfg to advertise offline servers!");
			return;
		}
		
		// Skip if on cooldown.
		if (g_advAdvertisements[iAdvertisementIndex].iAdvertisedTime != 0 &&
			g_advAdvertisements[iAdvertisementIndex].iCoolDownTime != 0 &&
			g_advAdvertisements[iAdvertisementIndex].iAdvertisedTime + g_advAdvertisements[iAdvertisementIndex].iCoolDownTime > GetTime())
			return;
		
		// Save the time when advertising.
		g_advAdvertisements[iAdvertisementIndex].iAdvertisedTime = GetTime();
		
		// Replace strings to show the server data
		FormatStringWithServerProperties(sMessageContent, sizeof(sMessageContent), iServerIndex);
		
		// If the server is Hidden, show only to authorized clients.		
		if(!g_srOtherServers[iServerIndex].bShowInServerList)
		{
			Format(sMessageContent, sizeof(sMessageContent), "%t", "ServerHiddenMenu", sMessageContent);
			
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
				if(ClientCanAccessToServer(iCurrentClient, iServerIndex))
					PrintToChatNewLine(iCurrentClient, sMessageContent);
		}
		else // Else, show to everyone :)
			PrintToChatAllNewLine(sMessageContent);
	}
}

// Loading an existing advertisement to the editable advertisement
stock void LoadAdvToEdit(int iAdvID)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadAdvToEdit | iAdvID = %d", iAdvID);
	
	g_advToEdit = g_advAdvertisements[iAdvID];
}

// Reseting the editable advertisement
stock void ResetAdvToEdit()
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- ResetAdvToEdit");
	
	Advertisement adv;
	g_advToEdit = adv;
}

// Copying a string to it's destination and adding a '...' if the string isn't fully shown.
stock void CopyStringWithDots(char[] sDest, int iDestLen, char[] sSource, int iSourceLen)
{
	strcopy(sDest, iDestLen, sSource);
			
	if(strlen(sSource) > iDestLen)
		strcopy(sDest[iDestLen - 4], iDestLen, "...");
}

// Clearing the advertisement array from a given position to the end.
stock void ClearAdvertisements(int iStartAdvertisement)
{
	Advertisement advClean;
	
	for (int iCurrentAdvertisement = iStartAdvertisement; iCurrentAdvertisement < MAX_ADVERTISEMENTS; iCurrentAdvertisement++)
		g_advAdvertisements[iCurrentAdvertisement] = advClean;
}

// Get the Player-Range for the advertisement from the string stored in the DB
stock int[] GetPlayerRangeFromString(const char[] sRangeString, int iMax)
{
	char sRangeSplitted[2][3];
	ExplodeString(sRangeString, "|", sRangeSplitted, sizeof(sRangeSplitted), sizeof(sRangeSplitted[]));
	
	int iResult[2];
	iResult[0] = !StrEqual(sRangeSplitted[0], "") ? StringToInt(sRangeSplitted[0]) : 0;
	iResult[1] = !StrEqual(sRangeSplitted[1], "") ? StringToInt(sRangeSplitted[1]) : iMax;
	
	return iResult;
}

// Print to all, with new line
stock void PrintToChatAllNewLine(char[] sMessage)
{
	char sMessageSplitted[12][128];
	ExplodeString(sMessage, "\\n", sMessageSplitted, sizeof(sMessageSplitted), sizeof(sMessageSplitted[]));

	for (int iCurrentRow = 0; iCurrentRow < sizeof(sMessageSplitted); iCurrentRow++)
		if(!StrEqual(sMessageSplitted[iCurrentRow], "", false))
			CPrintToChatAll(sMessageSplitted[iCurrentRow]);
}

// Print to client, with new line
stock void PrintToChatNewLine(int client, char[] sMessage)
{
	char sMessageSplitted[12][128];
	ExplodeString(sMessage, "\\n", sMessageSplitted, sizeof(sMessageSplitted), sizeof(sMessageSplitted[]));

	for (int iCurrentRow = 0; iCurrentRow < sizeof(sMessageSplitted); iCurrentRow++)
		if(!StrEqual(sMessageSplitted[iCurrentRow], "", false))
			CPrintToChat(client, sMessageSplitted[iCurrentRow]);
}

// Returning the advertisement index given the server and the advertisement mode
stock int FindAdvertisement(int iServer, int iAdvertisementMode)
{
	for (int iCurrentAdvertisement = 0; iCurrentAdvertisement < MAX_ADVERTISEMENTS; iCurrentAdvertisement++)
		if (g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise == iServer &&
			g_advAdvertisements[iCurrentAdvertisement].iRepeatTime == iAdvertisementMode)
			return iCurrentAdvertisement;
		
	return -1;
}

// Returning the server index given the server ID
stock int GetServerIndexByServerID(int iServerID)
{
	for (int iCurrentServer = 0; iCurrentServer < MAX_SERVERS; iCurrentServer++)
		if(g_srOtherServers[iCurrentServer].iServerID == iServerID)
			return iCurrentServer;
	return -1;
}