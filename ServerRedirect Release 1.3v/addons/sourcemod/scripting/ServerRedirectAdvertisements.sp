enum
{
	SQL_FIELD_ADVERTISEMENT_ID = 0,
	SQL_FIELD_ADVERTISEMENT_SERVER_ID,
	SQL_FIELD_ADVERTISEMENT_SERVER_ID_TO_ADVERTISE,
	SQL_FIELD_ADVERTISEMENT_REPEAT_TIME,
	SQL_FIELD_ADVERTISEMENT_COOLDOWN_TIME,
	SQL_FIELD_ADVERTISEMENT_PLAYER_RANGE,
	SQL_FIELD_ADVERTISEMENT_MESSAGE
}

public Plugin myinfo = 
{
	name = "[Server-List] Advertisements", 
	author = "Natanel 'LuqS'", 
	description = "Advertisements of 'Server-Redirect+', a variety of options to advertise other servers.", 
	version = "1.3", 
	url = "https://steamcommunity.com/id/luqsgood | Discord: LuqS#6505"
};

//====================[ EVENTS ]=====================//
public Action OnClientSayCommand(int client, const char[] command, const char[] args)
{
	// Client is editing something?
	if(g_iUpdateAdvProprietary[client] != UPDATE_NOTHING)
	{
		// Yes, but the client wants to exit edit mode without editing.
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
	
	// Loop throw all the advertisements (all valid advertisements).
	for (int iCurrentAdvertisement = 0; iCurrentAdvertisement < MAX_ADVERTISEMENTS; iCurrentAdvertisement++)
	{
		// Get the advertisement repeat time.
		int iAdvertisementRepeatTime = g_advAdvertisements[iCurrentAdvertisement].iRepeatTime;
		
		// If this advertisement is invalid, everything after it would be the same because we are loading the all of the advertisements to the start of the array.
		if(iAdvertisementRepeatTime != 0)
			break;
		
		// If this is the time to post the advertisement, go for it.
		if(g_iTimerCounter % iAdvertisementRepeatTime == 0)
			PostAdvertisement(g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise, ADVERTISEMENT_LOOP, iCurrentAdvertisement);
	}
	
	// Never gonna stop this timer! :)
	return Plugin_Continue;
}

//================[ MENUS & HANDLES ]================//
// sm_editsradv menu
public Action Command_EditServerRedirectAdvertisements(int client, int args)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Command_EditServerRedirectAdvertisements | Fired by %N (%d)", client, client);
	
	Menu mEditAdvertisements = new Menu(EditAdvertisementsMenuHandler);
	mEditAdvertisements.SetTitle("%t\n ", "MenuTitleEditAdvertisements", PREFIX_NO_COLOR);
	
	char sBuffer[64];
	Format(sBuffer, sizeof(sBuffer), "%t\n ", "AddAdvertisementEditMenu");
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
				g_advToEdit.iAdvID = -1;
			else
			{
				char sAdvertisementID[3];
				EditAdvertisementsMenu.GetItem(Clicked, sAdvertisementID, sizeof(sAdvertisementID));
				
				LoadAdvToEdit(StringToInt(sAdvertisementID));
			}
			
			EditAdvertisementPropertiesMenu(client);
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
	
	char sBuffer[128];
	
	Menu mAddAdvertisement = new Menu(AddAdvertisementMenuHandler);
	mAddAdvertisement.SetTitle("%s %t", PREFIX_NO_COLOR, g_advToEdit.iAdvID == -1 ? "MenuAddAdvActionAdd" : "MenuAddAdvActionEdit");
	
	Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvServerToAdv",  g_advToEdit.iServerIDToAdvertise);
	mAddAdvertisement.AddItem("AdvServerID", sBuffer);// 0
	
	Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvMode", g_advToEdit.iRepeatTime >= 0 ? "LOOP" : g_advToEdit.iRepeatTime == -1 ? "MAP" : "PLAYERS");
	mAddAdvertisement.AddItem("AdvMode", sBuffer);// 1
	
	Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvLoopTime", g_advToEdit.iRepeatTime);
	mAddAdvertisement.AddItem("AdvLoopTime", sBuffer, g_advToEdit.iRepeatTime >= 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE); // 2
	
	Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvCooldownTime", g_advToEdit.iCoolDownTime);
	mAddAdvertisement.AddItem("AdvLoopTime", sBuffer, g_advToEdit.iRepeatTime < 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE); // 3
	
	Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvPlayerRange", g_advToEdit.iPlayersRange[0], g_advToEdit.iPlayersRange[1]);
	mAddAdvertisement.AddItem("AdvPlayerRange", sBuffer, g_advToEdit.iRepeatTime == -2 ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE); // 4
	
	char sAdvMessage[32];
	CopyStringWithDots(sAdvMessage, sizeof(sAdvMessage), g_advToEdit.sMessageContent, sizeof(g_advToEdit.sMessageContent));
	
	Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvMessage", sAdvMessage);
	mAddAdvertisement.AddItem("AdvPlayerRange", sBuffer); // 5
	
	char sAdvID[4];
	IntToString(g_advToEdit.iAdvID, sAdvID, sizeof(sAdvID));
	Format(sBuffer, sizeof(sBuffer), "%t", g_advToEdit.iAdvID == -1 ? "MenuAddAdvActionAdd" : "MenuAddAdvActionEdit");
	mAddAdvertisement.AddItem(sAdvID, sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%t", g_advToEdit.iAdvID == -1 ? "MenuAddAdvActionReset" : "MenuAddAdvActionDelete");
	mAddAdvertisement.AddItem(sAdvID, sBuffer);
	
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
				{
					char sMenuTitle[128];
					Format(sMenuTitle, sizeof(sMenuTitle), "%t\n ", "MenuTitleSelectServerToAdv", PREFIX_NO_COLOR);
					SelectServerMainMenu(client, SelectServerToAdvMenuHandler, sMenuTitle, strlen(sMenuTitle), false);
				}
				case 1:
				{
					g_advToEdit.iRepeatTime = g_advToEdit.iRepeatTime >= 0 ? -1 : g_advToEdit.iRepeatTime == -1 ? -2 : 0;
					EditAdvertisementPropertiesMenu(client);
				}
				case 2:
					g_iUpdateAdvProprietary[client] = UPDATE_LOOP_TIME; 	// update loop time
				case 3:
					g_iUpdateAdvProprietary[client] = UPDATE_COOLDOWN_TIME; // update cooldown
				case 4:
					g_iUpdateAdvProprietary[client] = UPDATE_PLAYER_RANGE; 	// update player range
				case 5:
				{
					if(!StrEqual(g_advToEdit.sMessageContent, ""))
					{
						CPrintToChat(client, "%t", "EditingAdvMessage", PREFIX);
						PrintToChat(client, g_advToEdit.sMessageContent);
					}
						
					g_iUpdateAdvProprietary[client] = UPDATE_ADV_MESSAGE; 	// update adv message
				}
				case 6:
				{
					iAdvID == -1 ? AddAdvertisementToDB() : UpdateAdvertisementDB(iAdvID);		// Add / Edit adv
					
					ResetAdvToEdit();
				}
				case 7:
				{
					if(iAdvID == -1)
					{
						ResetAdvToEdit();
						EditAdvertisementPropertiesMenu(client);
					}
					else
						DeleteAdvertisementDB(iAdvID);
				}
			}
			
			if(1 < Clicked < 6)
			{
				CPrintToChat(client, "%t", "EnteredEditingMode", PREFIX);
				CPrintToChat(client, "%t", "AbortEditingMode", PREFIX);
			}
		}
		case MenuAction_Cancel:
			Command_EditServerRedirectAdvertisements(client, 0);
		case MenuAction_End:
			delete AddAdvertisementMenu;
	}
}


public int SelectServerToAdvMenuHandler(Menu SelectServerToAdv, MenuAction action, int client, int Clicked)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- SelectServerToAdvMenuHandler");
	
	switch(action)
	{
		case MenuAction_Select:
		{
			char sBuffer[MAX_CATEGORY_NAME_LENGHT];
			SelectServerToAdv.GetItem(Clicked, sBuffer, sizeof(sBuffer));
			
			if(StrContains(sBuffer, "[C]") != -1)
			{
				char sMenuTitle[128];
				Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MenuTitleSelectFromCategoryToAdv", PREFIX_NO_COLOR, sBuffer[4]);
				
				SelectServerMenu(client, sBuffer[4], SelectServerToAdvMenuHandler, sMenuTitle, strlen(sMenuTitle));
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


stock int LoadMenuAdvertisements(Menu hMenuToAdd)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadMenuAdvertisements");
	
	int iCurrentAdvertisement;
	char sBuffer[128];
	
	for (iCurrentAdvertisement = 0; iCurrentAdvertisement < MAX_ADVERTISEMENTS; iCurrentAdvertisement++) 
	{
		if(g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise != 0)
		{
			int iServerIndex = GetServerIndexByServerID(g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise);
			
			char sServerName[32], sAdvMessage[32];
			CopyStringWithDots(sAdvMessage, sizeof(sAdvMessage), g_advAdvertisements[iCurrentAdvertisement].sMessageContent, sizeof(g_advAdvertisements[].sMessageContent));
			
			if(iServerIndex != -1 && g_advAdvertisements[iCurrentAdvertisement].bActive)
				CopyStringWithDots(sServerName, sizeof(sServerName), g_srOtherServers[iServerIndex].sServerName, sizeof(g_srOtherServers[].sServerName));
			else
			{
				strcopy(sServerName, sizeof(sServerName), "*NOT ACTIVE*");
				
				LogError("%s #ERR: Couldn't find the server you are trying to advertise! (Server-ID - %d (%d), advertisement index - %d, Active - %b)",
				PREFIX_NO_COLOR,
				g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise,
				iServerIndex,
				iCurrentAdvertisement,
				g_advAdvertisements[iCurrentAdvertisement].bActive
				);
			}
			
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
// Create the DB Table if it's not already exists
void CreateAdvertisementsTable()
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- CreateAdvertisementsTable");
	
	DB.Query(T_OnAdvertisementsTableCreated, "CREATE TABLE IF NOT EXISTS `server_redirect_advertisements`(`id` INT NOT NULL AUTO_INCREMENT, `server_id` INT(11) NOT NULL, `server_id_to_adv` INT(11) NOT NULL, `adv_repeat_time` INT NOT NULL, `adv_cooldown_time` INT NOT NULL, `adv_players_range` VARCHAR(6) NOT NULL, `adv_message` VARCHAR(512) NOT NULL, PRIMARY KEY (`id`))", true, DBPrio_High);
}

// When the Table is created / we know there is a table
void T_OnAdvertisementsTableCreated(Handle owner, Handle hQuery, const char[] sError, any bStartTimer)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnAdvertisementsTableCreated");
	
	if (hQuery != INVALID_HANDLE)
		LoadAdvertisements(bStartTimer);
	else
		SetFailState("Couldn't create Advertisements Table [Error: %s]", sError);
}

// Load the Advertisements from the Table
void LoadAdvertisements(bool bStartTimer)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadAdvertisements");
	
	DB.Format(Query, sizeof(Query), "SELECT * FROM `server_redirect_advertisements` WHERE `server_id` = %d", g_srCurrentServer.iServerID);
	DB.Query(T_OnAdvertisementsRecive, Query, bStartTimer);
}

// When we get the advertisements
void T_OnAdvertisementsRecive(Handle owner, Handle hQuery, const char[] sError, any bStartTimer)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnAdvertisementsRecive");
		
	if(hQuery != INVALID_HANDLE)
	{
		char sRangeString[6];
		int iCurrentAdvertisement;
		
		for (iCurrentAdvertisement = 0; iCurrentAdvertisement < MAX_ADVERTISEMENTS && SQL_FetchRow(hQuery); iCurrentAdvertisement++) 
		{
			g_advAdvertisements[iCurrentAdvertisement].iAdvID					= SQL_FetchInt(hQuery, SQL_FIELD_ADVERTISEMENT_ID						);
			g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise 	= SQL_FetchInt(hQuery, SQL_FIELD_ADVERTISEMENT_SERVER_ID_TO_ADVERTISE	);
			g_advAdvertisements[iCurrentAdvertisement].iRepeatTime 				= SQL_FetchInt(hQuery, SQL_FIELD_ADVERTISEMENT_REPEAT_TIME				);
			g_advAdvertisements[iCurrentAdvertisement].iCoolDownTime 			= SQL_FetchInt(hQuery, SQL_FIELD_ADVERTISEMENT_COOLDOWN_TIME			);
			
			int iServerIndex = GetServerIndexByServerID(g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise);
			
			SQL_FetchString(hQuery, SQL_FIELD_ADVERTISEMENT_PLAYER_RANGE, sRangeString, sizeof(sRangeString));
			SQL_FetchString(hQuery, SQL_FIELD_ADVERTISEMENT_MESSAGE		, g_advAdvertisements[iCurrentAdvertisement].sMessageContent, sizeof(g_advAdvertisements[].sMessageContent));
			
			if(iServerIndex != -1)
			{
				g_advAdvertisements[iCurrentAdvertisement].bActive = true;	
				g_advAdvertisements[iCurrentAdvertisement].iPlayersRange = GetPlayerRangeFromString(sRangeString, g_srOtherServers[iServerIndex].iMaxPlayers); 
			}
			else
			{
				LogError("%s #ERR: Couldn't find the server you are trying to advertise! (Server-ID - %d, advertisement index - %d)",
				PREFIX_NO_COLOR,
				g_advAdvertisements[iCurrentAdvertisement].iServerIDToAdvertise,
				iCurrentAdvertisement
				);
			}
			
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
		
		ClearAdvertisements(iCurrentAdvertisement);
		
		if(!iCurrentAdvertisement)
			LogError("No Advertisements found in DB.");
			
		if(bStartTimer)
			CreateTimer(1.0, Timer_Loop, _, TIMER_REPEAT);
	}
	else
		SetFailState("Couldn't get server advertisements, Error: %s", sError);
}

// Add Advertisement to DB
void AddAdvertisementToDB()
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
		LogMessage("Query: %s", Query);
	
	DB.Query(T_UpdateAdvertisementQuery, Query, false);
}

// Update Advertisement in the DB
void UpdateAdvertisementDB(int iAdvertisement)
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
	
	if(g_cvPrintDebug.BoolValue)
		LogMessage("Query: %s", Query);
	
	DB.Query(T_UpdateAdvertisementQuery, Query, false);
}

// Delete Advertisement from the DB
void DeleteAdvertisementDB(int iAdvertisement)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- DeleteAdvertisementDB | iAdvertisement = %d", iAdvertisement);	
	
	Format(Query, sizeof(Query), "DELETE FROM `server_redirect_advertisements` WHERE `id` = %d", iAdvertisement);	
	
	if(g_cvPrintDebug.BoolValue)
		LogMessage("Query: %s", Query);
	
	DB.Query(T_UpdateAdvertisementQuery, Query, false);
}

// DB callback
void T_UpdateAdvertisementQuery(Handle owner, Handle hQuery, const char[] sError, any bStartTimer)
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

//===================[ HELPING ]=====================//
// Checking and posting an advertisement if it should be posted.
stock void PostAdvertisement(int iServerID, int iAdvertisementMode = ADVERTISEMENT_LOOP, int iAdvertisementIndex = -1)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- PostAdvertisement | int iServerID = %d, int iAdvertisementMode = %d, int iAdvertisementIndex = %d", iServerID, iAdvertisementMode, iAdvertisementIndex);
	
	// If the caller didn't give the advertisement, try to find it.
	if(iAdvertisementIndex == -1)
		iAdvertisementIndex = FindAdvertisement(iServerID, iAdvertisementMode);
	
	// If we still didn't find the advertisement, do not proceed.
	if(iAdvertisementIndex == -1)
		return;
		
	// If the advertisement is not active, do not proceed.
	if(!g_advAdvertisements[iAdvertisementIndex].bActive)
		return;
	
	// We are sure now that we have an advertisement to post and it's active, proceed.
	char sMessageContent[512];
	strcopy(sMessageContent, sizeof(sMessageContent), g_advAdvertisements[iAdvertisementIndex].sMessageContent);

	// Get Server index.
	int iServerIndex = GetServerIndexByServerID(iServerID);
	
	// Skip if Advertisements are disabled
	if(!g_bEnableAdvertisements)
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage("Advertisements are disabled, change 'PrefixRemover' to '1' in the plugin cfg to enable advertisements!");
		return;
	}
		
	// Skip if the server is down (unless we want to post offline servers).
	if(!g_bAdvertiseOfflineServers && !g_srOtherServers[iServerIndex].bServerStatus)
	{
		if(g_cvPrintDebug.BoolValue)
			LogMessage("Not advertising because server is offline, change 'AdvertiseOfflineServers' to '1' in the plugin cfg to advertise offline servers!");
		return;
	}
	
	// Skip if the advertisement is on cooldown.
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

// Clearing the advertisement array from a given position to the end.
stock void ClearAdvertisements(int iStartAdvertisement)
{
	Advertisement advClean;
	
	// Go throw all the advertisements (from where we told to start) and clean them 1 by 1 to the end.
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
			CPrintToChatAll(sMessageSplitted[iCurrentRow]);
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