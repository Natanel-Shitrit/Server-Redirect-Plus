#define TRANSLATION_NAME_LOOP_TIME		"LoopTimeTranslation"
#define TRANSLATION_NAME_COOLDOWN_TIME	"CooldownTimeTranslation"
#define TRANSLATION_NAME_PLAYER_RANGE	"PlayerRangeTranslation"
#define TRANSLATION_NAME_ADV_MESSAGE	"AdvMessageTranslation"

public Plugin myinfo = 
{
	name = "[Server-List] Advertisements", 
	author = "Natanel 'LuqS'", 
	description = "Advertisements of 'Server-Redirect+', a variety of options to advertise other servers.", 
	version = "2.3.0", 
	url = "https://steamcommunity.com/id/luqsgood | Discord: LuqS#6505"
};

//====================[ EVENTS ]=====================//
public Action OnClientSayCommand(int client, const char[] command, const char[] args)
{
	if(g_iUpdateAdvProprietary[client] != UPDATE_NOTHING)
	{
		if(!StrEqual(args, "-1"))
		{
			char sOldValue[16], sNewValue[16], sTranslationName[64];
			
			int iTime;
			if(UPDATE_LOOP_TIME <= g_iUpdateAdvProprietary[client] <= UPDATE_COOLDOWN_TIME)
			{
				iTime = StringToInt(args);
				
				if(iTime < 0)
				{
					CPrintToChat(client, "%t", "AdvertisementErrorInvalidValue", PREFIX, iTime);
					return Plugin_Handled;
				}
				
				// New Value of UPDATE_LOOP_TIME and UPDATE_COOLDOWN_TIME
				IntToString(iTime, sNewValue, sizeof(sNewValue));
			}
			
			switch(g_iUpdateAdvProprietary[client])
			{
				case UPDATE_LOOP_TIME:
				{
					sTranslationName = TRANSLATION_NAME_LOOP_TIME;
					
					// Old value of UPDATE_LOOP_TIME
					IntToString(g_advToEdit.iRepeatTime, sOldValue, sizeof(sOldValue));
					g_advToEdit.iRepeatTime = iTime;
				}
				case UPDATE_COOLDOWN_TIME:
				{
					sTranslationName = TRANSLATION_NAME_COOLDOWN_TIME;
					
					// Old value of UPDATE_COOLDOWN_TIME
					IntToString(g_advToEdit.iCoolDownTime, sOldValue, sizeof(sOldValue));
					g_advToEdit.iCoolDownTime = iTime;
				}
				case UPDATE_PLAYER_RANGE:
				{
					if(StrContains(args, "|") == -1 || strlen(args) > 6)
					{
						CPrintToChat(client, "%t", "AdvertisementErrorInvalidPlayerRange", PREFIX);
						CPrintToChat(client, "%t", "PlayerRangeStringExampleRow1"		 , PREFIX);
						CPrintToChat(client, "%t", "PlayerRangeStringExampleRow2"		 , PREFIX);
						return Plugin_Handled;
					}
					
					sTranslationName = TRANSLATION_NAME_PLAYER_RANGE;
					
					int iServerIndex = GetServerIndexByServerID(g_advToEdit.iAdvertisedServer);
					Server srServer;
					srServer = GetServerByIndex(iServerIndex);
					
					// Old value of UPDATE_PLAYER_RANGE
					Format(sOldValue, sizeof(sOldValue), "%d|%d", g_advToEdit.iPlayersRange[0], g_advToEdit.iPlayersRange[1]);
					
					g_advToEdit.iPlayersRange = GetPlayerRangeFromString(args, (iServerIndex >= 0 ? srServer.iMaxPlayers : MaxClients));
					
					// New value of UPDATE_PLAYER_RANGE
					Format(sNewValue, sizeof(sNewValue), "%d|%d", g_advToEdit.iPlayersRange[0], g_advToEdit.iPlayersRange[1]);
				}
				case UPDATE_ADV_MESSAGE:
				{
					sTranslationName = TRANSLATION_NAME_ADV_MESSAGE;
					
					// Old value of UPDATE_PLAYER_RANGE
					CopyStringWithDots(sOldValue, sizeof(sOldValue), g_advToEdit.sMessage);
					
					if(String_StartsWith(args, "<ADD>"))
						StrCat(g_advToEdit.sMessage, sizeof(g_advToEdit.sMessage), args[5]);
					else
						strcopy(g_advToEdit.sMessage, sizeof(g_advToEdit.sMessage), args);
					
					// New value of UPDATE_PLAYER_RANGE
					CopyStringWithDots(sNewValue, sizeof(sNewValue), g_advToEdit.sMessage);
				}
			}
			
			CPrintToChat(client, "%t", "UpdatedSuccessfullyTemplate", PREFIX, sTranslationName, sOldValue, sNewValue);
		}
		else
			CPrintToChat(client, "%t", "ExitEditMode", PREFIX);
		
		g_iUpdateAdvProprietary[client] = UPDATE_NOTHING;
		EditAdvertisementPropertiesMenu(client);
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//================[ MENUS & HANDLES ]================//
void OpenEditServerRedirectAdvertisementsMenu(int client)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- Command_EditServerRedirectAdvertisements | Fired by %N (%d)", client, client);
	
	Menu mEditAdvertisements = new Menu(EditAdvertisementsMenuHandler);
	mEditAdvertisements.SetTitle("%t\n ", "MenuTitleEditAdvertisements", PREFIX_NO_COLOR);
	
	char sTranslationTextBuffer[64];
	Format(sTranslationTextBuffer, sizeof(sTranslationTextBuffer), "%ts\n ", "MenuAdvAction", "Add");
	mEditAdvertisements.AddItem("", sTranslationTextBuffer);
	
	if(!LoadMenuAdvertisements(mEditAdvertisements))
		CPrintToChat(client, "%t", "NoAdvertisementsFound", PREFIX);
	
	mEditAdvertisements.ExitButton = true;
	mEditAdvertisements.Display(client, MENU_TIME_FOREVER);
}


int EditAdvertisementsMenuHandler(Menu EditAdvertisementsMenu, MenuAction action, int client, int Clicked)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- EditAdvertisementsMenuHandler");
	
	switch(action)
	{
		case MenuAction_Select:
		{
			g_advToEdit.iAdvID = 0;
			
			if(Clicked != 0)
			{
				char sAdvertisementID[3];
				EditAdvertisementsMenu.GetItem(Clicked, sAdvertisementID, sizeof(sAdvertisementID));
				
				LoadAdvToEdit(StringToInt(sAdvertisementID));
			}
			
			EditAdvertisementPropertiesMenu(client);
		}
		case MenuAction_Cancel:
		{
			if (Clicked == MenuCancel_Exit)
				Command_ServerList(client, 0);
		}
		case MenuAction_End:
			delete EditAdvertisementsMenu;
	}
}

// Edit Adv menu
void EditAdvertisementPropertiesMenu(int client)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- EditAdvertisementPropertiesMenu");
	
	char sBuffer[128];
	bool bNewAdvertisement = !g_advToEdit.iAdvID;
	
	Menu mAddAdvertisement = new Menu(AddAdvertisementMenuHandler);
	
	char sMenuPurpose[64];
	Format(sMenuPurpose, sizeof(sMenuPurpose), "%t", "MenuAdvAction", bNewAdvertisement ? "Add" : "Edit");
	mAddAdvertisement.SetTitle("%s %s", PREFIX_NO_COLOR, sMenuPurpose);
	
	Format(sBuffer, sizeof(sBuffer), "%t", "MenuAddAdvServerToAdv",  g_advToEdit.iAdvertisedServer);
	mAddAdvertisement.AddItem("AdvServerID", sBuffer);// 0
	
	Format(sBuffer, sizeof(sBuffer), "%t", "ChangeAdvPropery", "Mode", g_advToEdit.iRepeatTime >= ADVERTISEMENT_LOOP ? "LOOP" : g_advToEdit.iRepeatTime == ADVERTISEMENT_MAP ? "MAP" : "PLAYERS");
	mAddAdvertisement.AddItem("AdvMode", sBuffer);// 1
	
	IntToString(g_advToEdit.iRepeatTime, sBuffer, sizeof(sBuffer));
	Format(sBuffer, sizeof(sBuffer), "%t", "ChangeAdvPropery", "Loop Time", sBuffer);
	mAddAdvertisement.AddItem("AdvLoopTime", sBuffer, g_advToEdit.iRepeatTime >= ADVERTISEMENT_LOOP ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
	
	IntToString(g_advToEdit.iCoolDownTime, sBuffer, sizeof(sBuffer));
	Format(sBuffer, sizeof(sBuffer), "%t", "ChangeAdvPropery", "Cooldown Time", sBuffer);
	mAddAdvertisement.AddItem("AdvLoopTime", sBuffer, g_advToEdit.iRepeatTime < ADVERTISEMENT_LOOP ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
	
	Format(sBuffer, sizeof(sBuffer), "%d | %d", g_advToEdit.iPlayersRange[0], g_advToEdit.iPlayersRange[1]);
	Format(sBuffer, sizeof(sBuffer), "%t", "ChangeAdvPropery", "Player Range", sBuffer);
	mAddAdvertisement.AddItem("AdvPlayerRange", sBuffer, g_advToEdit.iRepeatTime == ADVERTISEMENT_PLAYERS_RANGE ? ITEMDRAW_DEFAULT : ITEMDRAW_IGNORE);
	
	CopyStringWithDots(sBuffer, 64, g_advToEdit.sMessage);
	Format(sBuffer, sizeof(sBuffer), "%t", "ChangeAdvPropery", "Message", sBuffer);
	mAddAdvertisement.AddItem("AdvMessage", sBuffer);
	
	char sAdvID[4];
	IntToString(g_advToEdit.iAdvID, sAdvID, sizeof(sAdvID));
	mAddAdvertisement.AddItem(sAdvID, sMenuPurpose);
	
	Format(sBuffer, sizeof(sBuffer), "%t", "MenuAdvAction", bNewAdvertisement ? "Reset" : "Delete");
	mAddAdvertisement.AddItem(sAdvID, sBuffer);
	
	mAddAdvertisement.ExitButton = true;
	
	mAddAdvertisement.Display(client, MENU_TIME_FOREVER);
}


int AddAdvertisementMenuHandler(Menu AddAdvertisementMenu, MenuAction action, int client, int Clicked)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- AddAdvertisementMenuHandler");
	
	switch(action)
	{
		case MenuAction_Select:
		{
			bool bNewAdvertisement = !g_advToEdit.iAdvID;
			
			switch(Clicked)
			{
				case 0:
				{
					char sMenuTitle[128];
					Format(sMenuTitle, sizeof(sMenuTitle), "%t\n ", "MenuTitleSelectServerToAdv", PREFIX_NO_COLOR);
					SelectServerMainMenu(client, SelectServerToAdvMenuHandler, "{id} | {shortname}", sMenuTitle, strlen(sMenuTitle), false);
				}
				case 1:
				{
					g_advToEdit.iRepeatTime = (g_advToEdit.iRepeatTime == ADVERTISEMENT_LOOP) ? ADVERTISEMENT_MAP :
												 g_advToEdit.iRepeatTime == ADVERTISEMENT_MAP ? ADVERTISEMENT_PLAYERS_RANGE : ADVERTISEMENT_LOOP;
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
					if(!StrEqual(g_advToEdit.sMessage, ""))
					{
						CPrintToChat(client, "%t", "EditingAdvMessage", PREFIX);
						PrintToChat(client, g_advToEdit.sMessage);
					}
						
					g_iUpdateAdvProprietary[client] = UPDATE_ADV_MESSAGE; 	// update adv message
				}
				case 6:
				{
					int iErrorID;
					
					if(!(iErrorID = IsValidAdvertisement(g_advToEdit)))
					{
						CPrintToChat(client, "%t", "ActionCompletedSuccessfully", PREFIX,
								(bNewAdvertisement ? g_advToEdit.AddToDB() : g_advToEdit.UpdateOnDB()) ? "Add" : "Edit");
						
						g_advToEdit.Reset();
					}
					else
					{
						PrintAdvertisementErrorMessage(client, iErrorID);
						EditAdvertisementPropertiesMenu(client);
					}
				}
				case 7:
				{
					if(bNewAdvertisement)
					{
						g_advToEdit.Reset();
						EditAdvertisementPropertiesMenu(client);
					}
					else
						g_advToEdit.DeleteFromDB();
				}
			}
			
			if(1 < Clicked < 6)
			{
				CPrintToChat(client, "%t", "EnteredEditingMode", PREFIX);
				CPrintToChat(client, "%t", "AbortEditingMode", PREFIX);
			}
		}
		case MenuAction_Cancel:
		{
			OpenEditServerRedirectAdvertisementsMenu(client);
		}
		case MenuAction_End:
		{
			delete AddAdvertisementMenu;
		}
	}
}

int SelectServerToAdvMenuHandler(Menu SelectServerToAdv, MenuAction action, int client, int Clicked)
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
				
				SelectServerMenu(client, sBuffer[4], "{id} | {shortname}", SelectServerToAdvMenuHandler, sMenuTitle, strlen(sMenuTitle));
			}
			else
			{
				g_advToEdit.iAdvertisedServer = GetServerByIndex(StringToInt(sBuffer)).iSteamAID;
				
				EditAdvertisementPropertiesMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete SelectServerToAdv;
		}
	}
}

int LoadMenuAdvertisements(Menu hMenuToAdd)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadMenuAdvertisements");
	
	Advertisement advCurrentAdvertisement;
	
	int iCurrentAdvertisement;
	char sBuffer[128];
	
	for (iCurrentAdvertisement = 0; iCurrentAdvertisement < g_hAdvertisements.Length; iCurrentAdvertisement++) 
	{
		advCurrentAdvertisement = GetAdvertisementByIndex(iCurrentAdvertisement);
		
		if(advCurrentAdvertisement.iAdvertisedServer != 0)
		{
			int iServerIndex = GetServerIndexByServerID(advCurrentAdvertisement.iAdvertisedServer);
			
			char sName[32], sAdvMessage[32];
			CopyStringWithDots(sAdvMessage, sizeof(sAdvMessage), advCurrentAdvertisement.sMessage);
			
			if(iServerIndex != -1 && advCurrentAdvertisement.bActive)
			{
				CopyStringWithDots(sName, sizeof(sName), GetServerByIndex(iServerIndex).sName);
			}
			else
			{
				strcopy(sName, sizeof(sName), "*NOT ACTIVE*");
				
				LogError("%s #ERR: Couldn't find the server you are trying to advertise! (Server-ID - %d (%d), advertisement index - %d, Active - %b)",
					PREFIX_NO_COLOR,
					advCurrentAdvertisement.iAdvertisedServer,
					iServerIndex,
					iCurrentAdvertisement,
					advCurrentAdvertisement.bActive
				);
			}
			
			Format(sBuffer, sizeof(sBuffer), "%s (ID %d - %s) | %s",
				sName,
				advCurrentAdvertisement.iAdvertisedServer,
				advCurrentAdvertisement.iRepeatTime > 0 ? "LOOP" : advCurrentAdvertisement.iRepeatTime == -1 ? "MAP" : "PLAYERS",
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
	
	DB.Query(T_OnAdvertisementsTableCreated, "CREATE TABLE IF NOT EXISTS `server_redirect_advertisements`(	`id` INT NOT NULL AUTO_INCREMENT, \
																											`advertising_server` INT(11) NOT NULL, \
																											`advertised_server` INT(11) NOT NULL, \
																											`repeat_time` INT NOT NULL, \
																											`cooldown_time` INT NOT NULL, \
																											`players_range` VARCHAR(6) NOT NULL, \
																											`message` VARCHAR(512) NOT NULL, \
																											PRIMARY KEY (`id`))",
																											true, DBPrio_High);
}

// When the Table is created / we know there is a table
void T_OnAdvertisementsTableCreated(Database owner, DBResultSet results, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnAdvertisementsTableCreated");
	
	if (results != INVALID_HANDLE)
		LoadAdvertisements();
	else
		SetFailState("Couldn't create Advertisements Table [Error: %s]", sError);
}

// Load the Advertisements from the Table
void LoadAdvertisements()
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadAdvertisements");
	
	DB.Format(Query, sizeof(Query), "SELECT * FROM `server_redirect_advertisements` WHERE `advertising_server` = %d", g_srThisServer.iSteamAID);
	DB.Query(T_OnAdvertisementsRecive, Query);
}

// When we get the advertisements
void T_OnAdvertisementsRecive(Database owner, DBResultSet results, const char[] sError, any data)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_OnAdvertisementsRecive");
		
	if(results != INVALID_HANDLE)
	{
		ArrayList hAdvertisements = new ArrayList(sizeof(Advertisement));
		char sRangeString[6];
		
		while(results.FetchRow()) 
		{
			Advertisement advCurrentAdvertisement;
			
			advCurrentAdvertisement.iAdvID			  = results.FetchInt(ADVERTISEMENTS_SQL_FIELD_ID				);
			advCurrentAdvertisement.iAdvertisedServer = results.FetchInt(ADVERTISEMENTS_SQL_FIELD_ADVERTISED_SERVER	);
			advCurrentAdvertisement.iRepeatTime 	  = results.FetchInt(ADVERTISEMENTS_SQL_FIELD_REPEAT_TIME		);
			advCurrentAdvertisement.iCoolDownTime 	  = results.FetchInt(ADVERTISEMENTS_SQL_FIELD_COOLDOWN_TIME		);
			
			int iServerIndex = GetServerIndexByServerID(advCurrentAdvertisement.iAdvertisedServer);
			
			if(iServerIndex != -1)
			{
				advCurrentAdvertisement.bActive = true;
				
				results.FetchString(ADVERTISEMENTS_SQL_FIELD_PLAYER_RANGE, sRangeString						, sizeof(sRangeString						));
				results.FetchString(ADVERTISEMENTS_SQL_FIELD_MESSAGE	 , advCurrentAdvertisement.sMessage , sizeof(advCurrentAdvertisement.sMessage	));
				
				advCurrentAdvertisement.iPlayersRange = GetPlayerRangeFromString(sRangeString, GetServerByIndex(iServerIndex).iMaxPlayers); 
			}
			else
			{
				advCurrentAdvertisement.bActive = false;
				
				LogError("%s #ERR: Couldn't find the server you are trying to advertise! (Server-ID - %d)",
					PREFIX_NO_COLOR,
					advCurrentAdvertisement.iAdvertisedServer
				);
			}
			
			if(g_cvPrintDebug.BoolValue)
				LogMessage("[T_OnAdvertisementsRecive -> LOOP] Advertisement %d: iAdvertisedServer - %d, iRepeatTime - %d, iCoolDownTime - %d, sMessage - %s",
					advCurrentAdvertisement.iAdvID,
					advCurrentAdvertisement.iAdvertisedServer,
					advCurrentAdvertisement.iRepeatTime,
					advCurrentAdvertisement.iCoolDownTime,
					advCurrentAdvertisement.sMessage
				);
				
			hAdvertisements.PushArray(advCurrentAdvertisement, sizeof(advCurrentAdvertisement));
		}
		
		if(g_hAdvertisements)
			delete g_hAdvertisements;
		
		g_hAdvertisements = hAdvertisements;
		
		if(g_cvPrintDebug.BoolValue && !g_hAdvertisements.Length)
			LogError("No Advertisements found in DB.");
	}
	else
		SetFailState("Couldn't get server advertisements, Error: %s", sError);
}

// DB callback
void T_UpdateAdvertisementQuery(Database owner, DBResultSet results, const char[] sError, any data)
{
	if (g_cvPrintDebug.BoolValue)
		LogMessage(" <-- T_UpdateAdvertisementQuery");
	
	if (results != INVALID_HANDLE)
		LoadAdvertisements();
	else
		LogError("Error in T_FakeFastQuery: %s", sError);
}

//===================[ HELPING ]=====================//
// Checking and posting an advertisement if it should be posted.
void PostAdvertisement(int iServerID, int iAdvertisementMode = ADVERTISEMENT_LOOP, int iAdvertisementIndex = -1)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- PostAdvertisement | int iServerID = %d, int iAdvertisementMode = %d, int iAdvertisementIndex = %d", iServerID, iAdvertisementMode, iAdvertisementIndex);
	
	// If the caller didn't give the advertisement, try to find it.
	if(iAdvertisementIndex == -1)
		iAdvertisementIndex = FindAdvertisement(iServerID, iAdvertisementMode);
	
	// If we still didn't find the advertisement, do not proceed.
	if(iAdvertisementIndex == -1)
		return;
	
	Advertisement advAdvertisementToPost;
	advAdvertisementToPost = GetAdvertisementByIndex(iAdvertisementIndex);
	
	// If the advertisement is not active, do not proceed.
	if(!advAdvertisementToPost.bActive)
		return;
	
	// We are sure now that we have an advertisement to post and it's active, proceed.
	char sMessage[512];
	strcopy(sMessage, sizeof(sMessage), advAdvertisementToPost.sMessage);

	// Get Server index.
	int iServerIndex = GetServerIndexByServerID(iServerID);
	
	Server srServer;
	srServer = GetServerByIndex(iServerIndex);
	
	// Skip if the advertisement is on cooldown.
	if (advAdvertisementToPost.iAdvertisedTime != 0 &&
		advAdvertisementToPost.iCoolDownTime != 0 &&
		advAdvertisementToPost.iAdvertisedTime + advAdvertisementToPost.iCoolDownTime > GetTime())
		return;
		
	// Save the time when advertising.
	advAdvertisementToPost.iAdvertisedTime = GetTime();
	
	// Replace strings to show the server data
	FormatStringWithServerProperties(sMessage, sizeof(sMessage), iServerIndex);
		
	// If the server is Hidden, show only to authorized clients.		
	if(!srServer.bShowInServerList)
	{
		Format(sMessage, sizeof(sMessage), "%s %t", sMessage, "ServerHiddenMenu");
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			if(IsClientInGame(iCurrentClient) && ClientCanAccessToServer(iCurrentClient, iServerIndex))
				PrintToChatNewLine(iCurrentClient, sMessage);
	}
	else // Else, show to everyone :)
		PrintToChatAllNewLine(sMessage);
}

// Loading an existing advertisement to the editable advertisement
void LoadAdvToEdit(int iAdvID)
{
	if(g_cvPrintDebug.BoolValue)
		LogMessage(" <-- LoadAdvToEdit | iAdvID = %d", iAdvID);
	
	g_advToEdit = GetAdvertisementByIndex(iAdvID);
}

// Get the Player-Range for the advertisement from the string stored in the DB
int[] GetPlayerRangeFromString(const char[] sRangeString, int iMax)
{
	char sRangeSplitted[2][3];
	ExplodeString(sRangeString, "|", sRangeSplitted, sizeof(sRangeSplitted), sizeof(sRangeSplitted[]));
	
	int iResult[2];
	iResult[0] = !StrEqual(sRangeSplitted[0], "") ? StringToInt(sRangeSplitted[0]) : 0;
	iResult[1] = !StrEqual(sRangeSplitted[1], "") ? StringToInt(sRangeSplitted[1]) : iMax;
	
	return iResult;
}

// Print to all, with new line
void PrintToChatAllNewLine(char[] sMessage)
{
	char sMessageSplitted[12][128];
	ExplodeString(sMessage, "\\n", sMessageSplitted, sizeof(sMessageSplitted), sizeof(sMessageSplitted[]));
	
	for (int iCurrentRow = 0; iCurrentRow < sizeof(sMessageSplitted); iCurrentRow++)
		if(!StrEqual(sMessageSplitted[iCurrentRow], "", false))
			CPrintToChatAll(sMessageSplitted[iCurrentRow]);
}

// Print to client, with new line
void PrintToChatNewLine(int client, char[] sMessage)
{
	char sMessageSplitted[12][128];
	ExplodeString(sMessage, "\\n", sMessageSplitted, sizeof(sMessageSplitted), sizeof(sMessageSplitted[]));

	for (int iCurrentRow = 0; iCurrentRow < sizeof(sMessageSplitted); iCurrentRow++)
		if(!StrEqual(sMessageSplitted[iCurrentRow], "", false))
			CPrintToChat(client, sMessageSplitted[iCurrentRow]);
}

// Returning the advertisement index given the server and the advertisement mode
int FindAdvertisement(int iServer, int iAdvertisementMode)
{
	Advertisement advCurrentAdvertisement;
	
	for (int iCurrentAdvertisement = 0; iCurrentAdvertisement < g_hAdvertisements.Length; iCurrentAdvertisement++)
	{
		advCurrentAdvertisement = GetAdvertisementByIndex(iCurrentAdvertisement);
		if (advCurrentAdvertisement.iAdvertisedServer == iServer && advCurrentAdvertisement.iRepeatTime == iAdvertisementMode)
			return iCurrentAdvertisement;
	}
			
	return -1;
}

// Returns 0 if the Advertisement is valid (otherwise the Error-ID)
int IsValidAdvertisement(Advertisement advToCheck)
{
	int iErrors, iServerIndex = GetServerIndexByServerID(advToCheck.iAdvertisedServer);
	
	// if the the server the player wants to advertise is invalid.
	if(iServerIndex == -1)
		iErrors |= (1 << ERROR_INVALID_SERVER_ID);
	
	int iServerMaxPlayers = GetServerByIndex(iServerIndex).iMaxPlayers;
	
	// If the Advertisement message is empty.
	if(StrEqual(advToCheck.sMessage, "", false))
		iErrors |= (1 << ERROR_EMPTY_MESSAGE_CONTENT);
	
	if(advToCheck.iRepeatTime == ADVERTISEMENT_PLAYERS_RANGE)
	{
		if(!(0 <= advToCheck.iPlayersRange[0] <= (iServerIndex >= 0 ? iServerMaxPlayers : MaxClients)))
			iErrors |= (1 << ERROR_INVALID_PLAYER_RANGE_START);
		
		if(!(0 <= advToCheck.iPlayersRange[1] <= (iServerIndex >= 0 ? iServerMaxPlayers : MaxClients)))
			iErrors |= (1 << ERROR_INVALID_PLAYER_RANGE_END);
			
		if(!(iErrors & (3 << ERROR_INVALID_PLAYER_RANGE_START)) && advToCheck.iPlayersRange[0] > advToCheck.iPlayersRange[1])
			iErrors |= (1 << ERROR_INVALID_PLAYER_RANGE);
	}
	
	return iErrors;
}

// Prints the errors of the advertisement according to the ErrorID
void PrintAdvertisementErrorMessage(int client, int iError)
{
	char sTranslationString[64];
	
	CPrintToChat(client, "%t", "AdvertisementErrorHeader", PREFIX);
	
	for (int iCurrentError = ERROR_INVALID_SERVER_ID; iCurrentError <= ERROR_INVALID_PLAYER_RANGE_END; iCurrentError++)
	{
		if(iError & (1 << iCurrentError))
		{
			Format(sTranslationString, sizeof(sTranslationString), "AdvertisementError%d", iCurrentError);
			CPrintToChat(client, "• %t", sTranslationString);
		}
	}
}