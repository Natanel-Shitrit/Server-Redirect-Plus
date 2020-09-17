#if defined _server_redirect_included_
  #endinput
#endif
#define _server_redirect_included_

// PREFIXs for the menus and chat messages
#define PREFIX " \x04[Server-Redirect+]\x01"
#define PREFIX_NO_COLOR "[Server-Redirect+]"

// Lenght as used in the Database.
#define MAX_SERVER_NAME_LENGHT 245
#define MAX_CATEGORY_NAME_LENGHT 32

//=======[ ADV TYPE ENUM ]======//
enum
{
	ADVERTISEMENT_PLAYERS_RANGE = -2,  	// USING DEFFRENCE CHECK
	ADVERTISEMENT_MAP 		 		, 	// USING DEFFRENCE CHECK
	ADVERTISEMENT_LOOP		 			// USING TIMER
}

//======[ ADV ERROR ENUM ]======//
enum
{
	// LOOP START
	ERROR_INVALID_SERVER_ID = 1	,
	ERROR_EMPTY_MESSAGE_CONTENT	,
	ERROR_INVALID_PLAYER_RANGE	,
	ERROR_INVALID_PLAYER_RANGE_START,
	ERROR_INVALID_PLAYER_RANGE_END	,
	// LOOP END
	ERROR_INVALID_LOOP_TIME,
	ERROR_INVALID_COOLDOWN_TIME
}

//======[ UPDATE ADV ENUM ]=====//
enum
{
	UPDATE_NOTHING = -1	,
	UPDATE_LOOP_TIME 	,
	UPDATE_COOLDOWN_TIME,
	UPDATE_PLAYER_RANGE ,
	UPDATE_ADV_MESSAGE
}

//====[ SERVER SEARCH ENUM ]====//
enum
{
	SERVER_SEARCH_BY_STEAM_ID = 0,
	SERVER_SEARCH_BY_BACKUP_ID
}

//======[ DB UPDATE ENUM ]======//
enum
{
	UPDATE_SERVER_STEAM_ID,
	UPDATE_SERVER_PLAYERS,
	UPDATE_SERVER_STATUS, 
	UPDATE_SERVER_START
}

//===[ SERVERS TABLE STRUCT ]===//
enum
{
	SQL_FIELD_BACKUP_ID = 1,
	SQL_FIELD_STEAM_ID,
	SQL_FIELD_NAME,
	SQL_FIELD_PASS,
	SQL_FIELD_IP,
	SQL_FIELD_PORT,
	SQL_FIELD_STATUS,
	SQL_FIELD_VISIBLE,
	SQL_FIELD_MAP,
	SQL_FIELD_PLAYERS,
	SQL_FIELD_RESERVED_SLOTS,
	SQL_FIELD_HIDDEN_SLOTS,
	SQL_FIELD_MAX_PLAYERS,
	SQL_FIELD_INCLUD_BOTS,
	SQL_FIELD_LAST_UPDATE,
	SQL_FIELD_TIMEOUT,
	SQL_FIELD_LAST_UPDATE_UNIX
}

//==[ CATEGORIES TABLE STRUCT ]==//
enum
{
	CATEGORY_SQL_FIELD_NAME = 1,
	CATEGORY_SQL_FIELD_ASSOCIATED_SERVER_STEAM_ID
}

/**
 * Gets the password of a server by IP.
 *
 * @param iServerIP32		IP32 address.
 * @param sBuffer			Buffer to store the password.
 * @param buffersize		Buffer size.
 *
 * @note stores the password in the given buffer.
 */
native Native_GetServerPasswordForRedirect(int iServerIP32, char[] sServerPasswordBuffer, int buffersize);

public SharedPlugin __pl_server_redirect = 
{
	name = "ServerList",
	file = "ServerListCore.smx",

	#if defined REQUIRE_PLUGIN
		required = 1
	#else
		required = 0
	#endif
};
