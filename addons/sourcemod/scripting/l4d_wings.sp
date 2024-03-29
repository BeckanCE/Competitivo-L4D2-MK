#define PLUGIN_VERSION 		"1.37"
#pragma semicolon 1

#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>

#define CVAR_FLAGS			FCVAR_NOTIFY
#define CHAT_TAG			"\x04[WINGS]\x01 "
#define CONFIG_SPAWNS		"data/l4d_wings.cfg"
#define	MAX_wingS			128


ConVar g_hCvarAllow, g_hCvarBots, g_hCvarChange, g_hCvarDetect, g_hCvarMake, g_hCvarMenu, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog, g_hCvarOpaq, g_hCvarPrecache, g_hCvarRand, g_hCvarSave, g_hCvarThird, g_hCvarWall;
ConVar g_hCvarMPGameMode;
Handle g_hCookie;
Menu g_hMenu, g_hMenus[MAXPLAYERS+1];
bool g_bCvarAllow, g_bMapStarted, g_bCvarBots, g_bCvarWall, g_bLeft4Dead2, g_bTranslation, g_bViewHooked, g_bValidMap;
int g_iCount, g_iCvarMake, g_iCvarFlags, g_iCvarOpaq, g_iCvarRand, g_iCvarSave, g_iCvarThird;
float g_fCvarChange, g_fCvarDetect;

float g_fSize[MAX_wingS], g_vAng[MAX_wingS][3], g_vPos[MAX_wingS][3];
char g_sModels[MAX_wingS][64], g_sNames[MAX_wingS][64];
char g_sSteamID[MAXPLAYERS+1][32];		// Stores client user id to determine if the blocked player is the same
int g_iwingIndex[MAXPLAYERS+1];			// Player wing entity reference
int g_iwingWalls[MAXPLAYERS+1];			// Hidden wing entity reference
int g_iSelected[MAXPLAYERS+1];			// The selected wing index (0 to MAX_wingS)
int g_iTarget[MAXPLAYERS+1];			// For admins to change clients wings
int g_iType[MAXPLAYERS+1];				// Stores selected wing to give players
bool g_bwingView[MAXPLAYERS+1];			// Player view of wing on/off (personal setting)
bool g_bwingOff[MAXPLAYERS+1];			// Lets players turn their wings on/off
bool g_bMenuType[MAXPLAYERS+1];			// Admin var for menu
bool g_bBlocked[MAXPLAYERS+1];			// Determines if the player is blocked from wings
bool g_bExternalCvar[MAXPLAYERS+1];		// If thirdperson view was detected (thirdperson_shoulder cvar)
bool g_bExternalProp[MAXPLAYERS+1];		// If thirdperson view was detected (netprop or revive actions)
bool g_bExternalState[MAXPLAYERS+1];	// If thirdperson view was detected
bool g_bCookieAuth[MAXPLAYERS+1];		// When cookies cached and client is authorized
Handle g_hTimerView[MAXPLAYERS+1];		// Thirdperson view when selecting wing
Handle g_hTimerDetect;



// ====================================================================================================
//					PLUGIN INFO / START / END
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D & L4D2] Wings",
	author = "Original hats author :SilverShot, Modified by Rory to fits wings",
	description = "Attaches specified models to players back.",
	version = PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if( test == Engine_Left4Dead ) g_bLeft4Dead2 = false;
	else if( test == Engine_Left4Dead2 ) g_bLeft4Dead2 = true;
	else
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	// Attachments API
	if( FindConVar("attachments_api_version") == null && (FindConVar("l4d2_swap_characters_version") != null || FindConVar("l4d_csm_version") != null) )
	{
		LogMessage("\n==========\nWarning: You should install \"[ANY] Attachments API\" to fix model attachments when changing character models: https://forums.alliedmods.net/showthread.php?t=325651\n==========\n");
	}

	// Use Priority Patch
	if( FindConVar("l4d_use_priority_version") == null )
	{
		LogMessage("\n==========\nWarning: You should install \"[L4D & L4D2] Use Priority Patch\" to fix attached models blocking +USE action: https://forums.alliedmods.net/showthread.php?t=327511\n==========\n");
	}
}

public void OnPluginStart()
{
	// Load config
	KeyValues hFile = OpenConfig();
	char sTemp[64];
	for( int i = 0; i < MAX_wingS; i++ )
	{
		IntToString(i+1, sTemp, sizeof(sTemp));
		if( hFile.JumpToKey(sTemp) )
		{
			hFile.GetString("mod", sTemp, sizeof(sTemp));

			TrimString(sTemp);
			if( sTemp[0] == 0 )
				break;

			if( FileExists(sTemp, true) )
			{
				hFile.GetVector("ang", g_vAng[i]);
				hFile.GetVector("loc", g_vPos[i]);
				g_fSize[i] = hFile.GetFloat("size", 1.0);
				g_iCount++;

				strcopy(g_sModels[i], sizeof(g_sModels[]), sTemp);

				hFile.GetString("name", g_sNames[i], sizeof(g_sNames[]));

				if( strlen(g_sNames[i]) == 0 )
					GetwingName(g_sNames[i], i);
			}
			else
				LogError("Cannot find the model '%s'", sTemp);

			hFile.Rewind();
		}
	}
	delete hFile;

	if( g_iCount == 0 )
		SetFailState("No models wtf?!");



	// Transactions
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/wingnames.phrases.txt");
	g_bTranslation = FileExists(sPath);

	if( g_bTranslation )
		LoadTranslations("wingnames.phrases");
	LoadTranslations("wings.phrases");
	LoadTranslations("core.phrases");



	// wings menu
	if( g_bTranslation == false )
	{
		g_hMenu = new Menu(wingMenuHandler);
		for( int i = 0; i < g_iCount; i++ )
			g_hMenu.AddItem(g_sModels[i], g_sNames[i]);
		g_hMenu.SetTitle("%t", "wing_Menu_Title");
		g_hMenu.ExitButton = true;
	}



	// Cvars
	g_hCvarAllow = CreateConVar(		"l4d_wings_allow",		"1",			"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarBots = CreateConVar(			"l4d_wings_bots",		"1",			"0=Disallow bots from spawning with wings. 1=Allow bots to spawn with wings.", CVAR_FLAGS, true, 0.0, true, 1.0 );
	g_hCvarChange = CreateConVar(		"l4d_wings_change",		"1.3",			"0=Off. Other value puts the player into thirdperson for this many seconds when selecting a wing.", CVAR_FLAGS );
	g_hCvarDetect = CreateConVar(		"l4d_wings_detect",		"0.3",			"0.0=Off. How often to detect thirdperson view. Also uses ThirdPersonShoulder_Detect plugin if available.", CVAR_FLAGS );
	g_hCvarMake = CreateConVar(			"l4d_wings_make",		"",				"Specify admin flags or blank to allow all players to spawn with a wing, requires the l4d_wings_random cvar to spawn.", CVAR_FLAGS );
	g_hCvarMenu = CreateConVar(			"l4d_wings_menu",		"",				"Specify admin flags or blank to allow all players access to the wings menu.", CVAR_FLAGS );
	g_hCvarModes = CreateConVar(		"l4d_wings_modes",		"",				"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff = CreateConVar(		"l4d_wings_modes_off",	"",				"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog = CreateConVar(		"l4d_wings_modes_tog",	"",				"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	g_hCvarOpaq = CreateConVar(			"l4d_wings_opaque",		"255", 			"How transparent or solid should the wings appear. 0=Translucent, 255=Opaque.", CVAR_FLAGS, true, 0.0, true, 255.0 );
	g_hCvarPrecache = CreateConVar(		"l4d_wings_precache",	"",				"Prevent pre-caching models on these maps, separate by commas (no spaces). Enabling plugin on these maps will crash the server.", CVAR_FLAGS );
	g_hCvarRand = CreateConVar(			"l4d_wings_random",		"1", 			"Attach a random wing when survivors spawn. 0=Never. 1=On round start. 2=Only first spawn (keeps the same wing next round).", CVAR_FLAGS, true, 0.0, true, 3.0 );
	g_hCvarSave = CreateConVar(			"l4d_wings_save",		"1", 			"0=Off, 1=Save the players selected wings and attach when they spawn or rejoin the server. Overrides the random setting.", CVAR_FLAGS, true, 0.0, true, 1.0 );
	g_hCvarThird = CreateConVar(		"l4d_wings_third",		"1", 			"0=Off, 1=When a player is in third person view, display their wing. Hide when in first person view.", CVAR_FLAGS, true, 0.0, true, 1.0 );
	g_hCvarWall = CreateConVar(			"l4d_wings_wall",		"1",			"0=Show wings glowing through walls, 1=Hide wings glowing when behind walls (creates 1 extra entity per wing).", CVAR_FLAGS, true, 0.0, true, 1.0 );
	CreateConVar(						"l4d_wings_version",		PLUGIN_VERSION,	"wings plugin version.",	FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,				"l4d_wings");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarBots.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarChange.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarDetect.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarMake.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarMenu.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarRand.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarSave.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarWall.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarOpaq.AddChangeHook(CvarChangeOpac);
	g_hCvarThird.AddChangeHook(CvarChangeThird);



	// Commands
	RegConsoleCmd("sm_wing",			Cmdwing,							"Displays a menu of wings allowing players to change what they are wearing.");
	RegConsoleCmd("sm_wingoff",		CmdwingOff,						"Toggle to turn on or off the ability of wearing wings.");
	RegConsoleCmd("sm_wingshow",		CmdwingShow,						"Toggle to see or hide your own wing.");
	RegConsoleCmd("sm_wingview",		CmdwingShow,						"Toggle to see or hide your own wing.");
	RegConsoleCmd("sm_wingshowon",	CmdwingShowOn,					"See your own wing.");
	RegConsoleCmd("sm_wingshowoff",	CmdwingShowOff,					"Hide your own wing.");
	RegAdminCmd("sm_wingclient",		CmdwingClient,	ADMFLAG_ROOT,	"Set a clients wing. Usage: sm_wingclient <#userid|name> [wing name or wing index: 0-128 (MAX_wingS)].");
	RegAdminCmd("sm_wingoffc",		CmdwingOffC,		ADMFLAG_ROOT,	"Toggle the ability of wearing wings on specific players.");
	RegAdminCmd("sm_wingc",			CmdwingC,		ADMFLAG_ROOT,	"Displays a menu listing players, select one to change their wing.");
	RegAdminCmd("sm_wingrandom",		CmdwingRand,		ADMFLAG_ROOT,	"Randomizes all players wings.");
	RegAdminCmd("sm_wingrand",		CmdwingRand,		ADMFLAG_ROOT,	"Randomizes all players wings.");
	RegAdminCmd("sm_wingadd",		CmdwingAdd,		ADMFLAG_ROOT,	"Adds specified model to the config (must be the full model path).");
	RegAdminCmd("sm_wingdel",		CmdwingDel,		ADMFLAG_ROOT,	"Removes a model from the config (either by index or partial name matching).");
	RegAdminCmd("sm_winglist",		CmdwingList,		ADMFLAG_ROOT,	"Displays a list of all the wing models (for use with sm_wingdel).");
	RegAdminCmd("sm_wingsave",		CmdwingSave,		ADMFLAG_ROOT,	"Saves the wing position and angels to the wing config.");
	RegAdminCmd("sm_wingload",		CmdwingLoad,		ADMFLAG_ROOT,	"Changes all players wings to the one you have.");
	RegAdminCmd("sm_wingang",		CmdAng,			ADMFLAG_ROOT,	"Shows a menu allowing you to adjust the wing angles (affects all wings/players).");
	RegAdminCmd("sm_wingpos",		CmdPos,			ADMFLAG_ROOT,	"Shows a menu allowing you to adjust the wing position (affects all wings/players).");
	RegAdminCmd("sm_wingsize",		CmdwingSize,		ADMFLAG_ROOT,	"Shows a menu allowing you to adjust the wing size (affects all wings/players).");

	g_hCookie = RegClientCookie("l4d_wings", "wing Type", CookieAccess_Protected);
}

public void OnPluginEnd()
{
	for( int i = 1; i <= MaxClients; i++ )
		Removewing(i);
}



// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnConfigsExecuted()
{
	IsAllowed();
}

public void ConVarChanged_Allow(Handle convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

public void ConVarChanged_Cvars(Handle convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	char sTemp[32];
	g_hCvarMake.GetString(sTemp, sizeof(sTemp));
	g_iCvarMake = ReadFlagString(sTemp);
	g_hCvarMenu.GetString(sTemp, sizeof(sTemp));
	g_iCvarFlags = ReadFlagString(sTemp);
	g_bCvarBots = g_hCvarBots.BoolValue;
	g_fCvarChange = g_hCvarChange.FloatValue;
	g_fCvarDetect = g_hCvarDetect.FloatValue;
	g_iCvarOpaq = g_hCvarOpaq.IntValue;
	g_iCvarRand = g_hCvarRand.IntValue;
	g_iCvarSave = g_hCvarSave.IntValue;
	g_iCvarThird = g_hCvarThird.IntValue;
	g_bCvarWall = g_hCvarWall.BoolValue;
}

void IsAllowed()
{
	bool bCvarAllow = g_hCvarAllow.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true && g_bValidMap == true )
	{
		g_bCvarAllow = true;

		if( g_iCvarThird )
			HookViewEvents();
		HookEvents();
		SpectatorwingHooks();

		for( int i = 1; i <= MaxClients; i++ )
		{
			g_bwingView[i] = false;
			g_iSelected[i] = GetRandomInt(0, g_iCount -1);
		}

		if( g_iCvarRand || g_iCvarSave )
		{
			int clientID;

			for( int i = 1; i <= MaxClients; i++ )
			{
				if( IsClientInGame(i) && GetClientTeam(i) == 2 )
				{
					clientID = GetClientUserId(i);

					if( g_iCvarSave && !IsFakeClient(i) )
					{
						OnClientCookiesCached(i);
						CreateTimer(0.3, TimerDelayCreate, clientID);
					}
					else if( g_iCvarRand )
					{
						CreateTimer(0.3, TimerDelayCreate, clientID);
					}
				}
			}
		}

		// if( g_bLeft4Dead2 && g_fCvarDetect )
		if( g_fCvarDetect )
		{
			delete g_hTimerDetect;
			g_hTimerDetect = CreateTimer(g_fCvarDetect, TimerDetect, _, TIMER_REPEAT);
		}
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false || g_bValidMap == false) )
	{
		g_bCvarAllow = false;

		UnhookViewEvents();
		UnhookEvents();

		for( int i = 1; i <= MaxClients; i++ )
		{
			Removewing(i);

			if( IsValidEntRef(g_iwingIndex[i]) )
			{
				for( int x = 1; x <= MaxClients; x++ )
				{
					if( IsClientInGame(x) )
					{
						SDKUnhook(g_iwingIndex[i], SDKHook_SetTransmit, Hook_SetSpecTransmit);
					}
				}
			}
		}
	}
}

int g_iCurrentMode;
bool IsAllowedGameMode()
{
	if( g_hCvarMPGameMode == null )
		return false;

	int iCvarModesTog = g_hCvarModesTog.IntValue;
	if( iCvarModesTog != 0 )
	{
		if( g_bMapStarted == false )
			return false;

		g_iCurrentMode = 0;

		int entity = CreateEntityByName("info_gamemode");
		if( IsValidEntity(entity) )
		{
			DispatchSpawn(entity);
			HookSingleEntityOutput(entity, "OnCoop", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnSurvival", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnVersus", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnScavenge", OnGamemode, true);
			ActivateEntity(entity);
			AcceptEntityInput(entity, "PostSpawnActivate");
			if( IsValidEntity(entity) ) // Because sometimes "PostSpawnActivate" seems to kill the ent.
				RemoveEdict(entity); // Because multiple plugins creating at once, avoid too many duplicate ents in the same frame
		}

		if( g_iCurrentMode == 0 )
			return false;

		if( !(iCvarModesTog & g_iCurrentMode) )
			return false;
	}

	char sGameModes[64], sGameMode[64];
	g_hCvarMPGameMode.GetString(sGameMode, sizeof(sGameMode));
	Format(sGameMode, sizeof(sGameMode), ",%s,", sGameMode);

	g_hCvarModes.GetString(sGameModes, sizeof(sGameModes));
	if( sGameModes[0] )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) == -1 )
			return false;
	}

	g_hCvarModesOff.GetString(sGameModes, sizeof(sGameModes));
	if( sGameModes[0] )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) != -1 )
			return false;
	}

	return true;
}

public void OnGamemode(const char[] output, int caller, int activator, float delay)
{
	if( strcmp(output, "OnCoop") == 0 )
		g_iCurrentMode = 1;
	else if( strcmp(output, "OnSurvival") == 0 )
		g_iCurrentMode = 2;
	else if( strcmp(output, "OnVersus") == 0 )
		g_iCurrentMode = 4;
	else if( strcmp(output, "OnScavenge") == 0 )
		g_iCurrentMode = 8;
}



// ====================================================================================================
//					OTHER BITS
// ====================================================================================================
public void OnMapStart()
{
	g_bMapStarted = true;
	g_bValidMap = true;

	char sCvar[512];
	g_hCvarPrecache.GetString(sCvar, sizeof(sCvar));

	if( sCvar[0] != '\0' )
	{
		char sMap[64];
		GetCurrentMap(sMap, sizeof(sMap));

		Format(sMap, sizeof(sMap), ",%s,", sMap);
		Format(sCvar, sizeof(sCvar), ",%s,", sCvar);

		if( StrContains(sCvar, sMap, false) != -1 )
			g_bValidMap = false;
	}

	if( g_bValidMap )
		for( int i = 0; i < g_iCount; i++ )
			PrecacheModel(g_sModels[i]);
}

public void OnMapEnd()
{
	g_bMapStarted = false;
}

public void OnClientAuthorized(int client, const char[] sSteamID)
{
	if( g_bBlocked[client] )
	{
		if( IsFakeClient(client) )
		{
			g_bBlocked[client] = false;
		}
		else if( strcmp(sSteamID, g_sSteamID[client]) )
		{
			strcopy(g_sSteamID[client], sizeof(g_sSteamID[]), sSteamID);
			g_bBlocked[client] = false;
		}
	}

	g_bMenuType[client] = false;

	CookieAuthTest(client);
}

public void OnClientCookiesCached(int client)
{
	if( g_bCvarAllow && g_iCvarSave && !IsFakeClient(client) )
	{
		// Get client cookies, set type if available or default.
		char sCookie[4];
		GetClientCookie(client, g_hCookie, sCookie, sizeof(sCookie));

		if( sCookie[0] == 0 )
		{
			g_iType[client] = 0;
		}
		else
		{
			int type = StringToInt(sCookie);
			g_iType[client] = type;
		}

		CookieAuthTest(client);
	}
}

void CookieAuthTest(int client)
{
	// Check if clients allowed to use wings otherwise delete cookie/wing
	if( g_iCvarMake && g_bCookieAuth[client] && !IsFakeClient(client) )
	{
		int flags = GetUserFlagBits(client);

		if( !(flags & ADMFLAG_ROOT) && !(flags & g_iCvarMake) )
		{
			g_iType[client] = 0;
			Removewing(client);
			SetClientCookie(client, g_hCookie, "0");
		}
	} else {
		g_bCookieAuth[client] = true;
	}
}

public void OnClientDisconnect(int client)
{
	g_bCookieAuth[client] = false;
	delete g_hTimerView[client];
}

KeyValues OpenConfig()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_SPAWNS);
	if( !FileExists(sPath) )
		SetFailState("Cannot find the file: \"%s\"", CONFIG_SPAWNS);

	KeyValues hFile = new KeyValues("models");
	if( !hFile.ImportFromFile(sPath) )
	{
		delete hFile;
		SetFailState("Cannot load the file: \"%s\"", CONFIG_SPAWNS);
	}
	return hFile;
}

void SaveConfig(KeyValues hFile)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_SPAWNS);
	hFile.Rewind();
	hFile.ExportToFile(sPath);
}

void GetwingName(char sTemp[64], int index)
{
	strcopy(sTemp, sizeof(sTemp), g_sModels[index]);
	ReplaceString(sTemp, sizeof(sTemp), "_", " ");
	int pos = FindCharInString(sTemp, '/', true) + 1;
	int len = strlen(sTemp) - pos - 3;
	strcopy(sTemp, len, sTemp[pos]);
}

bool IsValidClient(int client)
{
	if( client && IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client) )
		return true;
	return false;
}



// ====================================================================================================
//					CVAR CHANGES
// ====================================================================================================
public void CvarChangeOpac(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_iCvarOpaq = g_hCvarOpaq.IntValue;

	if( g_bCvarAllow )
	{
		int entity;
		for( int i = 1; i <= MaxClients; i++ )
		{
			entity = g_iwingIndex[i];
			if( IsValidClient(i) && IsValidEntRef(entity) )
			{
				SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
				SetEntityRenderColor(entity, 255, 255, 255, g_iCvarOpaq);
			}
		}
	}
}

public void CvarChangeThird(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_iCvarThird = g_hCvarThird.IntValue;

	if( g_bCvarAllow )
	{
		if( g_iCvarThird )
			HookViewEvents();
		else
			UnhookViewEvents();
	}
}



// ====================================================================================================
//					EVENTS
// ====================================================================================================
void HookEvents()
{
	HookEvent("round_start",		Event_Start);
	HookEvent("round_end",			Event_RoundEnd);
	HookEvent("player_death",		Event_PlayerDeath);
	HookEvent("player_spawn",		Event_PlayerSpawn);
	HookEvent("player_team",		Event_PlayerTeam);
}

void UnhookEvents()
{
	UnhookEvent("round_start",		Event_Start);
	UnhookEvent("round_end",		Event_RoundEnd);
	UnhookEvent("player_death",		Event_PlayerDeath);
	UnhookEvent("player_spawn",		Event_PlayerSpawn);
	UnhookEvent("player_team",		Event_PlayerTeam);
}

void HookViewEvents()
{
	if( g_bViewHooked == false )
	{
		g_bViewHooked = true;

		HookEvent("revive_success",			Event_First2);
		HookEvent("player_ledge_grab",		Event_Third1);
		HookEvent("lunge_pounce",			Event_Third2);
		HookEvent("pounce_end",				Event_First1);
		HookEvent("tongue_grab",			Event_Third2);
		HookEvent("tongue_release",			Event_First1);

		if( g_bLeft4Dead2 )
		{
			HookEvent("charger_pummel_start",		Event_Third2);
			HookEvent("charger_carry_start",		Event_Third2);
			HookEvent("charger_carry_end",			Event_First1);
			HookEvent("charger_pummel_end",			Event_First1);
		}
	}
}

void UnhookViewEvents()
{
	if( g_bViewHooked == false )
	{
		g_bViewHooked = true;

		UnhookEvent("revive_success",		Event_First2);
		UnhookEvent("player_ledge_grab",	Event_Third1);
		UnhookEvent("lunge_pounce",			Event_Third2);
		UnhookEvent("pounce_end",			Event_First1);
		UnhookEvent("tongue_grab",			Event_Third2);
		UnhookEvent("tongue_release",		Event_First1);

		if( g_bLeft4Dead2 )
		{
			UnhookEvent("charger_pummel_start",		Event_Third2);
			UnhookEvent("charger_carry_start",		Event_Third2);
			UnhookEvent("charger_carry_end",		Event_First1);
			UnhookEvent("charger_pummel_end",		Event_First1);
		}
	}
}

public void Event_Start(Event event, const char[] name, bool dontBroadcast)
{
	if( g_iCvarRand == 1 )
		CreateTimer(0.5, TimerRand, _, TIMER_FLAG_NO_MAPCHANGE);

	// if( g_bLeft4Dead2 && g_fCvarDetect )
	if( g_fCvarDetect )
	{
		delete g_hTimerDetect;
		g_hTimerDetect = CreateTimer(g_fCvarDetect, TimerDetect, _, TIMER_REPEAT);
	}
}

public Action TimerRand(Handle timer)
{
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsValidClient(i) )
		{
			Createwing(i, g_iType[i] ? g_iType[i] - 1: -1);
		}
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for( int i = 1; i <= MaxClients; i++ )
		Removewing(i);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if( !client || GetClientTeam(client) != 2 )
		return;

	Removewing(client);
	SpectatorwingHooks();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if( g_iCvarRand == 2 || g_iCvarSave )
	{
		int clientID = event.GetInt("userid");
		int client = GetClientOfUserId(clientID);

		if( client )
		{
			Removewing(client);
			CreateTimer(0.5, TimerDelayCreate, clientID);
		}
	}

	SpectatorwingHooks();
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int clientID = event.GetInt("userid");
	int client = GetClientOfUserId(clientID);

	Removewing(client);
	SpectatorwingHooks();

	if( g_iCvarRand )
		CreateTimer(0.1, TimerDelayCreate, clientID);
}

public Action TimerDelayCreate(Handle timer, any client)
{
	client = GetClientOfUserId(client);

	if( IsValidClient(client) && !g_bBlocked[client] )
	{
		bool fake = IsFakeClient(client);
		if( !g_bCvarBots && fake )
		{
			return;
		}

		if( !fake && g_iCvarMake != 0 )
		{
			int flags = GetUserFlagBits(client);

			if( !(flags & ADMFLAG_ROOT) && !(flags & g_iCvarMake) )
			{
				return;
			}
		}

		if( g_iCvarRand == 2 )
			Createwing(client, -2);
		else if( g_iCvarSave && !IsFakeClient(client) )
			Createwing(client, -3);
		else if( g_iCvarRand )
			Createwing(client, -1);
	}
}

public void Event_First1(Event event, const char[] name, bool dontBroadcast)
{
	EventView(GetClientOfUserId(event.GetInt("victim")), false);
}

public void Event_First2(Event event, const char[] name, bool dontBroadcast)
{
	EventView(GetClientOfUserId(event.GetInt("subject")), false);
}

public void Event_Third1(Event event, const char[] name, bool dontBroadcast)
{
	EventView(GetClientOfUserId(event.GetInt("userid")), true);
}

public void Event_Third2(Event event, const char[] name, bool dontBroadcast)
{
	EventView(GetClientOfUserId(event.GetInt("victim")), true);
}

void EventView(int client, bool bIsThirdPerson)
{
	if( IsValidClient(client) )
	{
		SetwingView(client, bIsThirdPerson);
	}
}

// Show wing when thirdperson view
public Action TimerDetect(Handle timer)
{
	if( g_bCvarAllow == false )
	{
		g_hTimerDetect = null;
		return Plugin_Stop;
	}

	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_bExternalCvar[i] == false && g_iwingIndex[i] && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) )
		{
			if( (g_bLeft4Dead2 && GetEntPropFloat(i, Prop_Send, "m_TimeForceExternalView") > GetGameTime()) || GetEntPropEnt(i, Prop_Send, "m_reviveTarget") != -1 )
			{
				if( g_bExternalProp[i] == false )
				{
					g_bExternalProp[i] = true;
					SetwingView(i, true);
				}
			}
			else
			{
				if( g_bExternalProp[i] == true )
				{
					g_bExternalProp[i] = false;
					SetwingView(i, false);
				}
			}
		}
	}

	return Plugin_Continue;
}

public void TP_OnThirdPersonChanged(int client, bool bIsThirdPerson)
{
	if( g_fCvarDetect )
	{
		if( bIsThirdPerson == true && g_bExternalCvar[client] == false )
		{
			g_bExternalCvar[client] = true;
			SetwingView(client, true);
		}
		else if( bIsThirdPerson == false && g_bExternalCvar[client] == true )
		{
			g_bExternalCvar[client] = false;
			SetwingView(client, false);
		}
	}
}

void SetwingView(int client, bool bIsThirdPerson)
{
	if( bIsThirdPerson && !g_bExternalState[client] )
	{
		g_bExternalState[client] = true;

		int entity = g_iwingIndex[client];
		if( entity && (entity = EntRefToEntIndex(entity)) != INVALID_ENT_REFERENCE )
			SDKUnhook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
	}
	else if( !bIsThirdPerson && g_bExternalState[client] )
	{
		g_bExternalState[client] = false;

		if( !g_bwingView[client] )
		{
			int entity = g_iwingIndex[client];
			if( entity && (entity = EntRefToEntIndex(entity)) != INVALID_ENT_REFERENCE )
				SDKHook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
		}
	}
}



// ====================================================================================================
//					BLOCK WINGS - WHEN SPECTATING IN 1ST PERSON VIEW
// ====================================================================================================
// Loop through wings, find valid ones, loop through for each client and add transmit hook for spectators
// Could be better instead of unhooking and hooking everyone each time, but quick and dirty addition...
void SpectatorwingHooks()
{
	for( int index = 1; index <= MaxClients; index++ )
	{
		if( IsValidEntRef(g_iwingIndex[index]) )
		{
			for( int i = 1; i <= MaxClients; i++ )
			{
				if( IsClientInGame(i) )
				{
					SDKUnhook(g_iwingIndex[index], SDKHook_SetTransmit, Hook_SetSpecTransmit);

					if( !IsPlayerAlive(i) )
					{
						// Must hook 1 frame later because SDKUnhook first and then SDKHook doesn't work, it won't be hooked for some reason.
						DataPack dPack = new DataPack();
						dPack.WriteCell(GetClientUserId(i));
						dPack.WriteCell(index);
						RequestFrame(OnFrameHooks, dPack);
					}
				}
			}
		}
	}
}

public void OnFrameHooks(DataPack dPack)
{
	dPack.Reset();

	int client = dPack.ReadCell();
	client = GetClientOfUserId(client);

	if( client && IsClientInGame(client) && !IsPlayerAlive(client) )
	{
		int index = dPack.ReadCell();
		SDKHook(EntRefToEntIndex(g_iwingIndex[index]), SDKHook_SetTransmit, Hook_SetSpecTransmit);
	}

	delete dPack;
}

public Action Hook_SetSpecTransmit(int entity, int client)
{
	if( !IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_iObserverMode") == 4 )
	{
		int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
		if( target > 0 && target <= MaxClients  && g_iwingIndex[target] == EntIndexToEntRef(entity) )
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}



// ====================================================================================================
//					COMMANDS
// ====================================================================================================
//					sm_wing
// ====================================================================================================
public Action Cmdwing(int client, int args)
{
	if( !g_bCvarAllow || !IsValidClient(client) )
	{
		CPrintToChat(client, "%s%T", CHAT_TAG, "No Access", client);
		return Plugin_Handled;
	}

	if( g_iCvarFlags != 0 )
	{
		int flags = GetUserFlagBits(client);

		if( !(flags & ADMFLAG_ROOT) && !(flags & g_iCvarFlags) )
		{
			CPrintToChat(client, "%s%T", CHAT_TAG, "No Access", client);
			return Plugin_Handled;
		}
	}

	if( args == 1 )
	{
		char sTemp[64];
		GetCmdArg(1, sTemp, sizeof(sTemp));

		if( strlen(sTemp) < 4 )
		{
			int index = StringToInt(sTemp);
			if( index < 1 || index >= (g_iCount + 1) )
			{
				CPrintToChat(client, "%s%T", CHAT_TAG, "wing_No_Index", client, index, g_iCount);
			}
			else
			{
				Removewing(client);

				if( Createwing(client, index - 1) )
				{
					ExternalView(client);
				}
			}
		}
		else
		{
			ReplaceString(sTemp, sizeof(sTemp), " ", "_");

			for( int i = 0; i < g_iCount; i++ )
			{
				if( StrContains(g_sModels[i], sTemp) != -1 || StrContains(g_sNames[i], sTemp) != -1 )
				{
					Removewing(client);

					if( Createwing(client, i) )
					{
						ExternalView(client);
					}
					return Plugin_Handled;
				}
			}

			CPrintToChat(client, "%s%T", CHAT_TAG, "wing_Not_Found", client, sTemp);
		}
	}
	else
	{
		ShowMenu(client);
	}

	return Plugin_Handled;
}

public int wingMenuHandler(Menu menu, MenuAction action, int client, int index)
{
	if( action == MenuAction_End && g_bTranslation == true && client != 0 )
	{
		delete menu;
	}
	else if( action == MenuAction_Select )
	{
		int target = g_iTarget[client];
		if( target )
		{
			g_iTarget[client] = 0;
			target = GetClientOfUserId(target);
			if( IsValidClient(target) )
			{
				char name[MAX_NAME_LENGTH];
				GetClientName(target, name, sizeof(name));

				CPrintToChat(client, "%s%T", CHAT_TAG, "wing_Changed", client, name);
				Removewing(target);

				if( Createwing(target, index) )
				{
					ExternalView(target);
				}
			}
			else
			{
				CPrintToChat(client, "%s%T", CHAT_TAG, "wing_Invalid", client);
			}

			return;
		}
		else
		{
			Removewing(client);
			if( Createwing(client, index) )
			{
				ExternalView(client);
			}
		}

		int menupos = menu.Selection;
		menu.DisplayAt(client, menupos, MENU_TIME_FOREVER);
	}
}

void ShowMenu(int client)
{
	if( g_bTranslation == false )
	{
		g_hMenu.Display(client, MENU_TIME_FOREVER);
	}
	else
	{
		char sTemp[128];
		Menu hTemp = new Menu(wingMenuHandler);
		hTemp.SetTitle("%T", "wing_Menu_Title", client);

		for( int i = 0; i < g_iCount; i++ )
		{
			Format(sTemp, sizeof(sTemp), "wing %d", i + 1, client);
			Format(sTemp, sizeof(sTemp), "%T", sTemp, client);
			hTemp.AddItem(g_sModels[i], sTemp);
		}

		hTemp.ExitButton = true;
		hTemp.Display(client, MENU_TIME_FOREVER);

		g_hMenus[client] = hTemp;
	}
}

// ====================================================================================================
//					sm_wingoff
// ====================================================================================================
public Action CmdwingOff(int client, int args)
{
	if( !g_bCvarAllow || g_bBlocked[client] )
	{
		CPrintToChat(client, "%s%T", CHAT_TAG, "No Access", client);
		return Plugin_Handled;
	}

	g_bwingOff[client] = !g_bwingOff[client];

	if( g_bwingOff[client] )
		Removewing(client);

	char sTemp[64];
	Format(sTemp, sizeof(sTemp), "%T", g_bwingOff[client] ? "wing_Off" : "wing_On", client);
	CPrintToChat(client, "%s%T", CHAT_TAG, "wing_Ability", client, sTemp);

	return Plugin_Handled;
}

// ====================================================================================================
//					sm_wingshow
// ====================================================================================================
public Action CmdwingShowOn(int client, int args)
{
	g_bwingView[client] = false;
	CmdwingShow(client, args);
}

public Action CmdwingShowOff(int client, int args)
{
	g_bwingView[client] = true;
	CmdwingShow(client, args);
}

public Action CmdwingShow(int client, int args)
{
	if( !g_bCvarAllow || g_bBlocked[client] )
	{
		CPrintToChat(client, "%s%T", CHAT_TAG, "No Access", client);
		return Plugin_Handled;
	}

	int entity = g_iwingIndex[client];
	if( entity == 0 || (entity = EntRefToEntIndex(entity)) == INVALID_ENT_REFERENCE )
	{
		CPrintToChat(client, "%s%T", CHAT_TAG, "wing_Missing", client);
		return Plugin_Handled;
	}

	g_bwingView[client] = !g_bwingView[client];
	if( !g_bwingView[client] )
		SDKHook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
	else
		SDKUnhook(entity, SDKHook_SetTransmit, Hook_SetTransmit);

	char sTemp[64];
	Format(sTemp, sizeof(sTemp), "%T", g_bwingView[client] ? "wing_On" : "wing_Off", client);
	CPrintToChat(client, "%s%T", CHAT_TAG, "wing_View", client, sTemp);
	return Plugin_Handled;
}



// ====================================================================================================
//					ADMIN COMMANDS
// ====================================================================================================
//					sm_wingrand / sm_ratrandom
// ====================================================================================================
public Action CmdwingRand(int client, int args)
{
	if( g_bCvarAllow )
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			Removewing(i);
		}

		int last = g_iCvarRand;
		g_iCvarRand = 1;

		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsValidClient(i) )
			{
				Createwing(i, -1);
			}
		}

		g_iCvarRand = last;
	}
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_wingclient
// ====================================================================================================
public Action CmdwingClient(int client, int args)
{
	if( args == 0 )
	{
		ReplyToCommand(client, "Usage: sm_wingclient <#userid|name> [wing name or wing index: 0-128 (MAX_wingS)].");
		return Plugin_Handled;
	}

	char sArg[32], target_name[MAX_TARGET_LENGTH];
	GetCmdArg(1, sArg, sizeof(sArg));

	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;

	if( (target_count = ProcessTargetString(
		sArg,
		client,
		target_list,
		MAXPLAYERS,
		COMMAND_FILTER_ALIVE, /* Only allow alive players */
		target_name,
		sizeof(target_name),
		tn_is_ml)) <= 0 )
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	int index = -1;
	if( args == 2 )
	{
		GetCmdArg(2, sArg, sizeof(sArg));

		if( strlen(sArg) > 3 )
		{
			for( int i = 0; i < g_iCount; i++ )
			{
				if( strcmp(g_sNames[i], sArg, false) == 0 )
				{
					index = i;
					break;
				}
			}
		} else {
			index = StringToInt(sArg);
		}
	}
	else
	{
		index = GetRandomInt(0, g_iCount - 1);
	}

	for( int i = 0; i < target_count; i++ )
	{
		if( GetClientTeam(target_list[i]) == 2 )
		{
			Removewing(target_list[i]);
			Createwing(target_list[i], index);
			ReplyToCommand(client, "[Wing] Set '%N' to '%s'", target_list[i], g_sNames[index]);
		}
	}

	return Plugin_Handled;
}

// ====================================================================================================
//					sm_wingc / sm_wingoffc
// ====================================================================================================
public Action CmdwingC(int client, int args)
{
	if( g_bCvarAllow )
		ShowPlayerList(client);
	return Plugin_Handled;
}

public Action CmdwingOffC(int client, int args)
{
	if( g_bCvarAllow )
	{
		g_bMenuType[client] = true;
		ShowPlayerList(client);
	}
	return Plugin_Handled;
}

void ShowPlayerList(int client)
{
	if( client && IsClientInGame(client) )
	{
		char sTempA[4], sTempB[MAX_NAME_LENGTH];
		Menu menu = new Menu(PlayerListMenur);

		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsValidClient(i) )
			{
				IntToString(GetClientUserId(i), sTempA, sizeof(sTempA));
				GetClientName(i, sTempB, sizeof(sTempB));
				menu.AddItem(sTempA, sTempB);
			}
		}

		if( g_bMenuType[client] )
			menu.SetTitle("Select player to disable wings:");
		else
			menu.SetTitle("Select player to change wing:");
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
}

public int PlayerListMenur(Menu menu, MenuAction action, int client, int index)
{
	if( action == MenuAction_End )
		delete menu;
	else if( action == MenuAction_Select )
	{
		char sTemp[4];
		menu.GetItem(index, sTemp, sizeof(sTemp));
		int target = StringToInt(sTemp);
		target = GetClientOfUserId(target);

		if( g_bMenuType[client] )
		{
			g_bMenuType[client] = false;
			g_bBlocked[target] = !g_bBlocked[target];

			if( g_bBlocked[target] == false )
			{
				if( IsValidClient(target) )
				{
					Removewing(target);
					Createwing(target);

					char name[MAX_NAME_LENGTH];
					GetClientName(target, name, sizeof(name));
					CPrintToChat(client, "%s%T", CHAT_TAG, "wing_Unblocked", client, name);
				}
			}
			else
			{
				char name[MAX_NAME_LENGTH];
				GetClientName(target, name, sizeof(name));
				GetClientAuthId(target, AuthId_Steam2, g_sSteamID[target], sizeof(g_sSteamID[]));
				CPrintToChat(client, "%s%T", CHAT_TAG, "wing_Blocked", client, name);
				Removewing(target);
			}
		}
		else
		{
			if( IsValidClient(target) )
			{
				g_iTarget[client] = GetClientUserId(target);

				ShowMenu(client);
			}
		}
	}
}

// ====================================================================================================
//					sm_wingadd
// ====================================================================================================
public Action CmdwingAdd(int client, int args)
{
	if( !g_bCvarAllow )
		return Plugin_Handled;

	if( args == 1 )
	{
		if( g_iCount < MAX_wingS )
		{
			char sTemp[64], sKey[4];
			GetCmdArg(1, sTemp, sizeof(sTemp));

			if( FileExists(g_sModels[g_iCount], true) )
			{
				strcopy(g_sModels[g_iCount], sizeof(g_sModels[]), sTemp);
				g_vAng[g_iCount] = view_as<float>({ 0.0, 0.0, 0.0 });
				g_vPos[g_iCount] = view_as<float>({ 0.0, 0.0, 0.0 });
				g_fSize[g_iCount] = 1.0;

				KeyValues hFile = OpenConfig();
				IntToString(g_iCount+1, sKey, sizeof(sKey));
				hFile.JumpToKey(sKey, true);
				hFile.SetString("mod", sTemp);
				SaveConfig(hFile);
				delete hFile;
				g_iCount++;
				ReplyToCommand(client, "%sAdded wing '\x04%s\x01' %d/%d", CHAT_TAG, sTemp, g_iCount, MAX_wingS);
			}
			else
				ReplyToCommand(client, "%sCould not find the model '\x05%s'. Not adding to config.", CHAT_TAG, sTemp);
		}
		else
		{
			ReplyToCommand(client, "%sReached maximum number of wings (%d)", CHAT_TAG, MAX_wingS);
		}
	}
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_wingdel
// ====================================================================================================
public Action CmdwingDel(int client, int args)
{
	if( !g_bCvarAllow )
		return Plugin_Handled;

	if( args == 1 )
	{
		char sTemp[64];
		int index;
		bool bDeleted;

		GetCmdArg(1, sTemp, sizeof(sTemp));
		if( strlen(sTemp) < 4 )
		{
			index = StringToInt(sTemp);
			if( index < 1 || index >= (g_iCount + 1) )
			{
				ReplyToCommand(client, "%sCannot find the wing index %d, values between 1 and %d", CHAT_TAG, index, g_iCount);
				return Plugin_Handled;
			}
			index--;
			strcopy(sTemp, sizeof(sTemp), g_sModels[index]);
		}
		else
		{
			index = 0;
		}

		char sModel[64], sKey[4];
		KeyValues hFile = OpenConfig();

		for( int i = index; i < MAX_wingS; i++ )
		{
			IntToString(i+1, sKey, sizeof(sKey));
			if( hFile.JumpToKey(sKey) )
			{
				if( bDeleted )
				{
					IntToString(i, sKey, sizeof(sKey));
					hFile.SetSectionName(sKey);

					strcopy(g_sModels[i-1], sizeof(g_sModels[]), g_sModels[i]);
					strcopy(g_sNames[i-1], sizeof(g_sNames[]), g_sNames[i]);
					g_vAng[i-1] = g_vAng[i];
					g_vPos[i-1] = g_vPos[i];
					g_fSize[i-1] = g_fSize[i];
				}
				else
				{
					hFile.GetString("mod", sModel, sizeof(sModel));
					if( StrContains(sModel, sTemp) != -1 )
					{
						ReplyToCommand(client, "%sYou have deleted the wing '\x04%s\x01'", CHAT_TAG, sModel);
						hFile.DeleteKey(sTemp);

						g_iCount--;
						bDeleted = true;

						if( g_bTranslation == false )
						{
							g_hMenu.RemoveItem(i);
						}
						else
						{
							for( int x = 1; x <= MAXPLAYERS; x++ )
							{
								if( g_hMenus[x] != null )
								{
									g_hMenus[x].RemoveItem(i);
								}
							}
						}
					}
				}
			}

			hFile.Rewind();
			if( i == MAX_wingS - 1 )
			{
				if( bDeleted )
					SaveConfig(hFile);
				else
					ReplyToCommand(client, "%sCould not delete wing, did not find model '\x04%s\x01'", CHAT_TAG, sTemp);
			}
		}
		delete hFile;
	}
	else
	{
		int index = g_iSelected[client];

		if( g_bTranslation == false )
		{
			CPrintToChat(client, "%s%T \x01", CHAT_TAG, "wing_Wearing", client, g_sNames[index]);
		}
		else
		{
			char sMsg[128];
			Format(sMsg, sizeof(sMsg), "wing %d", index + 1);
			Format(sMsg, sizeof(sMsg), "%T", sMsg, client);
			CPrintToChat(client, "%s%T \x01", CHAT_TAG, "wing_Wearing", client, sMsg);
		}
	}
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_winglist
// ====================================================================================================
public Action CmdwingList(int client, int args)
{
	for( int i = 0; i < g_iCount; i++ )
		ReplyToCommand(client, "%d) %s", i+1, g_sModels[i]);
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_wingload
// ====================================================================================================
public Action CmdwingLoad(int client, int args)
{
	if( g_bCvarAllow && IsValidClient(client) )
	{
		int selected = g_iSelected[client];
		PrintToChat(client, "%sLoaded wing '\x04%s\x01' on all players.", CHAT_TAG, g_sModels[selected]);

		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsValidClient(i) )
			{
				Removewing(i);
				Createwing(i, selected);
			}
		}
	}
	return Plugin_Handled;
}

// ====================================================================================================
//					sm_wingsave
// ====================================================================================================
public Action CmdwingSave(int client, int args)
{
	if( g_bCvarAllow && IsValidClient(client) )
	{
		int entity = g_iwingIndex[client];
		if( IsValidEntRef(entity) )
		{
			KeyValues hFile = OpenConfig();
			int index = g_iSelected[client];

			char sTemp[4];
			IntToString(index+1, sTemp, sizeof(sTemp));
			if( hFile.JumpToKey(sTemp) )
			{
				float vAng[3], vPos[3];
				float fSize;

				GetEntPropVector(entity, Prop_Send, "m_angRotation", vAng);
				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vPos);
				hFile.SetVector("ang", vAng);
				hFile.SetVector("loc", vPos);
				g_vAng[index] = vAng;
				g_vPos[index] = vPos;

				if( g_bLeft4Dead2 )
				{
					fSize = GetEntPropFloat(entity, Prop_Send, "m_flModelScale");
					if( fSize == 1.0 )
					{
						if( hFile.GetFloat("size", 999.9) != 999.9 )
							hFile.DeleteKey("size");
					}
					else
						hFile.SetFloat("size", fSize);

					g_fSize[index] = fSize;
				}

				SaveConfig(hFile);
				PrintToChat(client, "%sSaved '\x04%s\x01' wing origin and angles.", CHAT_TAG, g_sModels[index]);
			}
			else
			{
				PrintToChat(client, "%s\x05Warning: \x01Could not save '\x04%s\x01' wing origin and angles.", CHAT_TAG, g_sModels[index]);
			}
			delete hFile;
		}
	}

	return Plugin_Handled;
}

// ====================================================================================================
//					sm_wingang
// ====================================================================================================
public Action CmdAng(int client, int args)
{
	if( g_bCvarAllow )
		ShowAngMenu(client);
	return Plugin_Handled;
}

void ShowAngMenu(int client)
{
	if( !IsValidClient(client) )
	{
		CPrintToChat(client, "%s%T", CHAT_TAG, "No Access", client);
		return;
	}

	Menu menu = new Menu(AngMenuHandler);

	menu.AddItem("", "X + 10.0");
	menu.AddItem("", "Y + 10.0");
	menu.AddItem("", "Z + 10.0");
	menu.AddItem("", "Reset");
	menu.AddItem("", "X - 10.0");
	menu.AddItem("", "Y - 10.0");
	menu.AddItem("", "Z - 10.0");

	menu.SetTitle("Set wing angles.");
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int AngMenuHandler(Menu menu, MenuAction action, int client, int index)
{
	if( action == MenuAction_End )
		delete menu;
	else if( action == MenuAction_Cancel )
	{
		if( index == MenuCancel_ExitBack )
			ShowAngMenu(client);
	}
	else if( action == MenuAction_Select )
	{
		if( IsValidClient(client) )
		{
			ShowAngMenu(client);

			float vAng[3];
			int entity;
			for( int i = 1; i <= MaxClients; i++ )
			{
				if( IsValidClient(i) )
				{
					entity = g_iwingIndex[i];
					if( IsValidEntRef(entity) )
					{
						GetEntPropVector(entity, Prop_Send, "m_angRotation", vAng);

						switch( index )
						{
							case 0: vAng[0] += 10.0;
							case 1: vAng[1] += 10.0;
							case 2: vAng[2] += 10.0;
							case 3: vAng = view_as<float>({0.0,0.0,0.0});
							case 4: vAng[0] -= 10.0;
							case 5: vAng[1] -= 10.0;
							case 6: vAng[2] -= 10.0;
						}

						TeleportEntity(entity, NULL_VECTOR, vAng, NULL_VECTOR);
					}
				}
			}

			CPrintToChat(client, "%sNew wing angles: %f %f %f", CHAT_TAG, vAng[0], vAng[1], vAng[2]);
		}
	}
}

// ====================================================================================================
//					sm_wingpos
// ====================================================================================================
public Action CmdPos(int client, int args)
{
	if( g_bCvarAllow )
		ShowPosMenu(client);
	return Plugin_Handled;
}

void ShowPosMenu(int client)
{
	if( !IsValidClient(client) )
	{
		CPrintToChat(client, "%s%T", CHAT_TAG, "No Access", client);
		return;
	}

	Menu menu = new Menu(PosMenuHandler);

	menu.AddItem("", "X + 0.5");
	menu.AddItem("", "Y + 0.5");
	menu.AddItem("", "Z + 0.5");
	menu.AddItem("", "Reset");
	menu.AddItem("", "X - 0.5");
	menu.AddItem("", "Y - 0.5");
	menu.AddItem("", "Z - 0.5");

	menu.SetTitle("Set wing position.");
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int PosMenuHandler(Menu menu, MenuAction action, int client, int index)
{
	if( action == MenuAction_End )
		delete menu;
	else if( action == MenuAction_Cancel )
	{
		if( index == MenuCancel_ExitBack )
			ShowPosMenu(client);
	}
	else if( action == MenuAction_Select )
	{
		if( IsValidClient(client) )
		{
			ShowPosMenu(client);

			float vPos[3];
			int entity;
			for( int i = 1; i <= MaxClients; i++ )
			{
				if( IsValidClient(i) )
				{
					entity = g_iwingIndex[i];
					if( IsValidEntRef(entity) )
					{
						GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vPos);

						switch( index )
						{
							case 0: vPos[0] += 0.5;
							case 1: vPos[1] += 0.5;
							case 2: vPos[2] += 0.5;
							case 3: vPos = view_as<float>({0.0,0.0,0.0});
							case 4: vPos[0] -= 0.5;
							case 5: vPos[1] -= 0.5;
							case 6: vPos[2] -= 0.5;
						}

						TeleportEntity(entity, vPos, NULL_VECTOR, NULL_VECTOR);
					}
				}
			}

			CPrintToChat(client, "%sNew wing origin: %f %f %f", CHAT_TAG, vPos[0], vPos[1], vPos[2]);
		}
	}
}

// ====================================================================================================
//					sm_wingsize
// ====================================================================================================
public Action CmdwingSize(int client, int args)
{
	if( g_bCvarAllow )
		ShowSizeMenu(client);
	return Plugin_Handled;
}

void ShowSizeMenu(int client)
{
	if( !IsValidClient(client) )
	{
		CPrintToChat(client, "%s%T", CHAT_TAG, "No Access", client);
		return;
	}

	if( !g_bLeft4Dead2 )
	{
		CPrintToChat(client, "%sCannot set wing size in L4D1.", CHAT_TAG);
		return;
	}

	Menu menu = new Menu(SizeMenuHandler);

	menu.AddItem("", "+ 0.1");
	menu.AddItem("", "- 0.1");
	menu.AddItem("", "+ 0.5");
	menu.AddItem("", "- 0.5");
	menu.AddItem("", "+ 1.0");
	menu.AddItem("", "- 1.0");
	menu.AddItem("", "Reset");

	menu.SetTitle("Set wing size.");
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int SizeMenuHandler(Menu menu, MenuAction action, int client, int index)
{
	if( action == MenuAction_End )
		delete menu;
	else if( action == MenuAction_Cancel )
	{
		if( index == MenuCancel_ExitBack )
			ShowSizeMenu(client);
	}
	else if( action == MenuAction_Select )
	{
		if( IsValidClient(client) )
		{
			ShowSizeMenu(client);

			float fSize;
			int entity;
			for( int i = 1; i <= MaxClients; i++ )
			{
				entity = g_iwingIndex[i];
				if( IsValidEntRef(entity) )
				{
					fSize = GetEntPropFloat(entity, Prop_Send, "m_flModelScale");

					switch( index )
					{
						case 0: fSize += 0.1;
						case 1: fSize -= 0.1;
						case 2: fSize += 0.5;
						case 3: fSize -= 0.5;
						case 4: fSize += 1.0;
						case 5: fSize -= 1.0;
						case 6: fSize = 1.0;
					}

					SetEntPropFloat(entity, Prop_Send, "m_flModelScale", fSize);
				}
			}

			CPrintToChat(client, "%sNew wing scale: %f", CHAT_TAG, fSize);
		}
	}
}



// ====================================================================================================
//					wing STUFF
// ===================================================================================================
void Removewing(int client)
{
	// wing entity
	int entity = g_iwingIndex[client];
	g_iwingIndex[client] = 0;

	if( IsValidEntRef(entity) )
		RemoveEntity(entity);

	// Hidden entity
	entity = g_iwingWalls[client];
	g_iwingWalls[client] = 0;

	if( IsValidEntRef(entity) )
		RemoveEntity(entity);
}

bool Createwing(int client, int index = -1)
{
	if( g_bBlocked[client] || g_bwingOff[client] || IsValidEntRef(g_iwingIndex[client]) == true || IsValidClient(client) == false )
		return false;

	if( index == -1 ) // Random wing
	{
		if( g_iCvarRand == 0 ) return false;

		if( g_iCvarFlags != 0 )
		{
			if( IsFakeClient(client) )
				return false;

			int flags = GetUserFlagBits(client);
			if( !(flags & ADMFLAG_ROOT) && !(flags & g_iCvarFlags) )
				return false;
		}

		index = GetRandomInt(0, g_iCount -1);
		g_iType[client] = index + 1;
	}
	else if( index == -2 ) // Previous random wing
	{
		if( g_iCvarRand != 2 ) return false;

		index = g_iType[client];
		if( index == 0 )
		{
			index = GetRandomInt(1, g_iCount);
		}

		index--;
	}
	else if( index == -3 ) // Saved wings
	{
		index = g_iType[client];

		if( index == 0 )
		{
			if( IsFakeClient(client) == true )
				return false;
			else
			{
				if(  g_iCvarRand == 0 ) return false;

				index = GetRandomInt(1, g_iCount);
			}
		}
		index--;
	}
	else // Specified wing
	{
		g_iType[client] = index + 1;
	}

	if( g_iCvarSave && !IsFakeClient(client) )
	{
		char sNum[4];
		IntToString(index + 1, sNum, sizeof(sNum));
		SetClientCookie(client, g_hCookie, sNum);
	}

	// Fix showing glow through walls, break glow inheritance by attaching wings to info_target.
	// Method by "Marttt": https://forums.alliedmods.net/showpost.php?p=2737781&postcount=21
	int target;

	if( g_bCvarWall )
	{
		target = CreateEntityByName("info_target");
		DispatchSpawn(target);
	}

	int entity = CreateEntityByName("prop_dynamic_override");
	if( entity != -1 )
	{
		SetEntityModel(entity, g_sModels[index]);
		DispatchSpawn(entity);
		if( g_bLeft4Dead2 )
		{
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", g_fSize[index]);
		}

		if( g_bCvarWall )
		{
			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", target);
			TeleportEntity(target, g_vPos[index], NULL_VECTOR, NULL_VECTOR);

			SetVariantString("!activator");
			AcceptEntityInput(target, "SetParent", client);
			SetVariantString("medkit");
			AcceptEntityInput(target, "SetParentAttachment");
			TeleportEntity(target, g_vPos[index], NULL_VECTOR, NULL_VECTOR);

			g_iwingWalls[client] = EntIndexToEntRef(target);
		} else {
			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", client);
			SetVariantString("medkit");
			AcceptEntityInput(entity, "SetParentAttachment");
			TeleportEntity(entity, g_vPos[index], NULL_VECTOR, NULL_VECTOR);
		}

		// Lux
		AcceptEntityInput(entity, "DisableCollision");
		SetEntProp(entity, Prop_Send, "m_noGhostCollision", 1, 1);
		SetEntProp(entity, Prop_Data, "m_CollisionGroup", 0x0004);
		SetEntPropVector(entity, Prop_Send, "m_vecMins", view_as<float>({0.0, 0.0, 0.0}));
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", view_as<float>({0.0, 0.0, 0.0}));
		// Lux

		TeleportEntity(g_bCvarWall ? target : entity, g_vPos[index], g_vAng[index], NULL_VECTOR);
		SetEntProp(entity, Prop_Data, "m_iEFlags", 0);

		if( g_iCvarOpaq )
		{
			SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
			SetEntityRenderColor(entity, 255, 255, 255, g_iCvarOpaq);
		}

		g_iSelected[client] = index;
		g_iwingIndex[client] = EntIndexToEntRef(entity);

		if( !g_bwingView[client] )
			SDKHook(entity, SDKHook_SetTransmit, Hook_SetTransmit);

		if( g_bTranslation == false )
		{
			CPrintToChat(client, "%s%T \x01", CHAT_TAG, "wing_Wearing", client, g_sNames[index]);
		}
		else
		{
			char sMsg[128];
			Format(sMsg, sizeof(sMsg), "wing %d", index + 1);
			Format(sMsg, sizeof(sMsg), "%T", sMsg, client);
			CPrintToChat(client, "%s%T \x01", CHAT_TAG, "wing_Wearing", client, sMsg);
		}

		SpectatorwingHooks();
		return true;
	}

	return false;
}

void ExternalView(int client)
{
	if( g_fCvarChange && g_bLeft4Dead2 )
	{
		g_bExternalState[client] = false;

		EventView(client, true);

		// Survivor Thirdperson plugin sets 99999.3.
		if( GetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView") == 99999.3 )
			return;

		delete g_hTimerView[client];
		g_hTimerView[client] = CreateTimer(g_fCvarChange + (g_fCvarChange >= 2.0 ? 0.4 : 0.2), TimerEventView, GetClientUserId(client));

		SetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView", GetGameTime() + g_fCvarChange);
	}
}

public Action TimerEventView(Handle timer, any client)
{
	client = GetClientOfUserId(client);
	if( client )
	{
		EventView(client, false);
		g_hTimerView[client] = null;
	}
}

public Action Hook_SetTransmit(int entity, int client)
{
	if( EntIndexToEntRef(entity) == g_iwingIndex[client] )
		return Plugin_Handled;
	return Plugin_Continue;
}

bool IsValidEntRef(int entity)
{
	if( entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		return true;
	return false;
}



// ====================================================================================================
//					COLORS.INC REPLACEMENT
// ====================================================================================================
void CPrintToChat(int client, char[] message, any ...)
{
	static char buffer[256];
	VFormat(buffer, sizeof(buffer), message, 3);

	ReplaceString(buffer, sizeof(buffer), "{default}",		"\x01");
	ReplaceString(buffer, sizeof(buffer), "{white}",		"\x01");
	ReplaceString(buffer, sizeof(buffer), "{cyan}",			"\x03");
	ReplaceString(buffer, sizeof(buffer), "{lightgreen}",	"\x03");
	ReplaceString(buffer, sizeof(buffer), "{orange}",		"\x04");
	ReplaceString(buffer, sizeof(buffer), "{green}",		"\x04"); // Actually orange in L4D2, but replicating colors.inc behaviour
	ReplaceString(buffer, sizeof(buffer), "{olive}",		"\x05");

	PrintToChat(client, buffer);
}