# Server-Redirect-Plus

## What is 'Server-Redirect+'?
'Server-Redirect+' is an interactive, auto-updated Server-List that can contain all of your CS:GO game servers, advertise them and let players hop between them from a game menu, with just 1 click!

With 'Server-Redirect+' you can see real time information about each server in the server-list.\
You can categorize, sort and view the servers however you like, with a formattable menus and more features.

Advertise your servers with dynamic advertisements, print the real time information.\
You can set an interval for the advertisement to post every x seconds and even print on events such as map change or when there are certian number of players in the server.

## Demonstration Video
[![Server-Redirect-Plus Demonstration Video](http://img.youtube.com/vi/fOj7ho6Y-6I/0.jpg)](http://www.youtube.com/watch?v=fOj7ho6Y-6I)

## Download
To find the latest stable release: ['Server-Redirect+' Releases](https://github.com/Natanel-Shitrit/Server-Redirect-Plus/releases)

Downloading the repository itself is also an option.\
but, it's not always guaranteed to be stable!

## Requirements / Dependencies:
To compile and use this plugin you need these dependencies on every server:\
 - [Sourcemod 1.10+ Compiler.](https://www.sourcemod.net/downloads.php?branch=1.10)
 - [sm-redirect-core](https://github.com/Wend4r/sm-redirect-core)
 - [LobbySessionFixer](https://github.com/komashchenko/LobbySessionFixer)
 - [PTaH](https://github.com/komashchenko/PTaH)

## Compile instructions:
1. Use 1.11 sourcemod compiler
2. Make sure you have all includes: `sourcemod`, `redirect_core`, `multicolors` and 'ServerList'.
3. Make sure `ServerRedirectCore.sp`, `ServerRedirectMenus.sp` and `ServerRedirectAdvertisements.sp` is in the same directory.
4. You should only compile `ServerRedirectCore.sp`, all other files are included in there.
5. Have fun 😉

## Installation and Configuration
Okay, you have some servers and you want to install this awesome plugin, you came to the right place.

Firstly, **Download** the plugin from the [**'Server-Redirect+' Releases**](https://github.com/Natanel-Shitrit/Server-Redirect-Plus/releases) page. (Or alternatively download the repository itself.)\
Next, extract the files into the server path (in '/csgo/', where you can spot the 'addons' and 'cfg' folders).

Now, let's configure the *database* config. navigate to '`/csgo/addons/sourcemod/configs/`' and open '`databases.cfg`'.\
We will need to make a config for the 'Server-Redirect+' plugin so it will know what database credentials to use.

Use the following template:
```
"ServerRedirect"
{
    "driver"    "mysql"                   // This plugin uses mysql, please do not change this section :)
    "host"      "DATABASE_SERVER_IP"      // The server IP, If you do not know if you have a database, you probably do not have one. (Search online about it)
    "database"  "DATABASE_TO_USE"         // The database that you want to use (the database is where the tables will be, not refeered to the server itself)
    "user"      "DATABASE_USER"           // The user must have access to the database you mention in the 'database' section
    "pass"      "DATABASE_USER_PASSWORD"  // The password to the user
    "port"      "DATABASE_SERVER_IP"      // The database doesn't always have a port (in that case note this section), but when there is a port, it's important to specify it.
}
```
Great, Now the plugin should connect to the database.

Before we start using the plugin let's configure it, navigate to '`/csgo/addons/sourcemod/configs/ServerRedirect/`' and open '`Config.cfg`'.\
Here's each setting and what it does:

  - `ServerBackupID` - This Server Backup-ID will be saved in the Database (it has to be unique, no error if you duplicate it but it will cause problems, so just make sure you don't duplicate it) and it will be used to identify the specific server when the server Steam Account-ID has changed.\
  Note: This section isn't required for the plugin to run. but, without it the server will be deleted from the database on shutdown. (if you change your server token often you it's RECOMMENDED use it).

  - `ServerName` - This name will be shown on the Server-List Menu. Leave blank if you want to use your Server Hostname.
  
  - `PrefixRemover` - String to remove from the server name (useful for removing prefixes)\
  For example, if i have `PrefixRemover = SomeName ` and `ServerName = SomeName Retake #1` this will result `{shortname}` to be `Retake #1`.
  
  - `ServerCategories` - Categories of the server in the Server-List Menu.\
  The category section helps you organize your servers and improve the user experience.
  If you want the server to appear in the main menu add `GLOBAL` to the categories 
  to add multiple commands, separate them with a comma (,).\
  
  - `ShowSeverInServerList` - Whether this server should appear in the Server-List or not.
  
  - `ShowBots` - Whether to include bots in the player count or not.
  
  - `ServerListCommands` - The commnad(s) that will open the Server-List menu.\
  Note: Commands must start with "sm_", to add multiple commands, separate them with a comma (,).\
  Example: `"sm_servers,sm_serverlist,sm_sl"`
  
  - `MenuFormat` - This is how the menu will be formatted.\
  See **'Server Assets for 'MenuFormat' and Advertisements'** to see the avilable assets that can be used\
  Example: `{shortname} ({current} / {max} - {map})` will show: `Retake #1 (7 / 10 - de_dust2)` for example.
  
  - `EnableAdvertisements` - Whether or not offline servers will be Advertised.
  
  - `ServerTimeOut` - The amount of time (in minutes) before this server will be deleted from the database after the last update.
  
Run the plugin and confirm everything works fine.
If the plugin **does not** work and you get an error message, go to the **'Known issues and fixes'** section.

## Server Assets for 'MenuFormat' and Advertisements
  - Sever Short Name (read 'PrefixRemover') - `{shortname}`
  - Sever Long Name (without 'PrefixRemover') - `{longname}`
  - Current Player Count - `{current}`
  - Max Players - `{max}`
  - Server Map - `{map}`
  - Server Category - `{category}`
  - Server Status (ONLINE / OFFLINE) - `{status}`
  - Player-Count (Players & Bots / Real Players) - `{bots}`
  - Server ID - `{id}`
  - Server IP - `{ip}`
  - Server Port - `{port}`
   
Note: If you have an idea for new things that can be useful for 'MenuFormat' or Advertisements, you can [open an issue](https://github.com/Natanel-Shitrit/Server-Redirect-Plus/issues/new).

## Usage
### User commands:
The commands you configured at the `ServerListCommands` config section will open the "Server-List", this is where all the servers are going be listed.\
After selecting a server, a menu will be shown with:
  1. The title will show the the `Server Name` and the `Server IP` + `Server Port`.
  2. `Number Of Players` and the server and the `Maximum Amount Of Players` that can be in the server. (If there are reserved slots and they are not hidden / you have permission to see the hidden reserved slots, they will be after the `Maximum Amount Of Players`)
  3. `Server Map` - Current played map in the server.
  4. A button to `Print Server Info` into the chat.
  5. A button to `Join The Server` - Will redirect them to the server.

### Advertisements:
#### How to enter the advertisements menu:
  - Open the server list and click the `Edit Advertisements` option.
<img src="https://i.imgur.com/wisM4TX.png" width="300">

  - Use the `sm_editsradv` (`/editsradv` or `!editsradv`).
#### Create an advertisement:
<img src="https://i.imgur.com/DD9a22y.png" width="300">

  1. `Server to advertise` - the server that will be advertised, in the future there will be an option to select multiple servers and a category.
  
  2. `Advertisement mode` - There are 3 modes:\
    - `LOOP` - Every `X` seconds the advertisement will be posted.\
    - `MAP` - Every time a map changes it will post the advertisement.\
    - `PLAYERS` - Every time the players are between `X` to `Y` the advertisement will be posted.\
      \* For `MAP` and `PLAYERS` there is a `Cooldown` option so it will not spam-post the advertisement.
      
  3. For `LOOP` mode, this is the `loop time` - how many seconds should pass before posting the advertisement.\
     For `MAP` and `PLAYERS` that will be the `Cooldown time` - how much time should pass before posting again.
     
  4. For `PLAYERS` there is the player range, the syntx is: `<Minimum Number Of Player>|<Maximum Number Of Player>`\
     Example: `3|5` (between 3 players to 5 players)
  
  5. `Advertisement Message` - the message that will be shown when the advertisement will be posted, you can use the `Server Assets` in the message and it will be replaced with the real-time info from the database.\
  Note: if you reached the max characters in the chat and you want to add to the message you can write `<ADD>` in the start of the message and it will append the message to the end of the existing message.

## ConVars
  - `server_redirect_other_servers_update_interval` - The number of seconds between other servers update. (default - `20.0`)
  - `server_redirect_server_update_interval` - The number of seconds the plugin will wait before updating player count in the SQL server. (default - `20.0`)
  - `server_redirect_debug_mode` - Whether or not to print debug messages in server console (default - `0`, You shouldn't turn this on unless you contacted me and we are trying to identify a bug, if you will turn this on it will just spam your server console with debug prints related to this plugin.)

## Overrides
Each override provides you the option to give different `Admin Group(s)` different things:
  - `server_redirect_join_full_bypass` - Will allow the `Admin Group(s)` to get redirected even if the server is full.
  - `server_redirect_edit_advertisements` - Will allow the `Admin Group(s)` to edit / add advertisements.
  - `server_redirect_show_hidden_servers` - Will show hidden servers to this `Admin Group(s)`.
  - `server_redirect_use_reserved_slots` - Will alow the `Admin Group(s)` to get redirected using the `Reserved Slot(s)`.

## Known issues and fixes
### "Couldn't get the server IP":
If you incounter this error, you need to set the public IP manually by adding this following command into the server (srdc) launch options: `+net_public_adr <Put here the public IP>`.

### "This plugin is for CSGO only":
As it sounds, currently you can only use this plugin for CS:GO.

### "Cannot Connect To MySQL Server! | Error: ...." OR "Couldn't create Advertisements Table \[Error: %s\]" OR "Couldn't get server advertisements, Error: %s":
Error with your MySQL server, to find out how to fix the error you got, google it.

### "Couldn't load plugin config.":
`Config.cfg` is missing from `sourcemod/confings/ServerRedirect/`.

### "Couldn't get the Server Steam Account ID, Please manually configure ServerID in the plugin config":
If you didn't configure the `ServerID` section in the config and the plugin failed to get the `Server Steam-ID`, go to the config and put a `ServerID`.

### If you get any other error and you are sure it's caused by this plugin feel free to [open an issue](https://github.com/Natanel-Shitrit/Server-Redirect-Plus/issues/new).
