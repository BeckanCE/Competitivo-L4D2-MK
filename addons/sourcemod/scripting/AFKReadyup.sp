#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#define REQUIRE_PLUGIN

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

ConVar
	g_cvarDebug,
	g_cvarEnable,
	g_cvarPlayerIgnore,
	g_cvarTime,
	g_cvarReadyFooter,
	g_cvarShowTimer;

int
	g_iPlayerAFK[MAXPLAYERS + 1];

float
	g_fPlayerLastPos[MAXPLAYERS + 1][3],
	g_fPlayerLastEyes[MAXPLAYERS + 1][3];

Handle
	g_hStartTimerAFK;

bool
	g_bReadyUpAvailable;

enum L4DTeam
{
	L4DTeam_Unassigned = 0,
	L4DTeam_Spectator  = 1,
	L4DTeam_Survivor   = 2,
	L4DTeam_Infected   = 3
}

/*****************************************************************
			P L U G I N   I N F O
*****************************************************************/


public Plugin myinfo =
{
	name		= "AFK on Readyup",
	author		= "lechuga",
	description = "Manage AFK players in the readyup",
	version		= "1.0",
	url			= ""
};

/*****************************************************************
			F O R W A R D   P U B L I C S
*****************************************************************/

public void OnAllPluginsLoaded()
{
	g_bReadyUpAvailable = LibraryExists("readyup");
}

public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, "readyup"))
		g_bReadyUpAvailable = true;
}

public void OnLibraryRemoved(const char[] sName)
{
	if (StrEqual(sName, "readyup"))
		g_bReadyUpAvailable = false;
}

public void OnPluginStart()
{
	LoadTranslations("AFKReadyup.phrases");
	g_cvarDebug		   = CreateConVar("sm_debug", "0", "Debug messages", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvarEnable	   = CreateConVar("sm_afk_enable", "1", "Activate the plugin", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarPlayerIgnore = CreateConVar("sm_afk_ignore", "1", "Ignore players ready", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarTime		   = CreateConVar("sm_afk_time", "40", "Time to move players", FCVAR_NOTIFY, true, 0.0);
	g_cvarReadyFooter  = CreateConVar("sm_afk_footer", "1", "Show ready footer", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarShowTimer	   = CreateConVar("sm_afk_show", "10", "Show timer to players, 0 is disable", FCVAR_NOTIFY, true, 0.0);

	AutoExecConfig(false, "AFKReadyup");

	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_Say);

	HookEvent("entity_shoved", Event_PlayerAction);
	HookEvent("player_shoved", Event_PlayerAction);
	HookEvent("player_hurt", Event_PlayerAction);
	HookEvent("player_hurt_concise", Event_PlayerAction);

	HookEvent("player_jump", Event_PlayerJump);
	HookEvent("player_team", Event_PlayerTeam);
	HookEntityOutput("func_button_timed", "OnPressed", Event_OnPressed);
}

Action Command_Say(int iClient, int iArgs)
{
	if (!g_cvarEnable.BoolValue || !g_bReadyUpAvailable || !IsInReady())
		return Plugin_Continue;

	if (!IsValidClientIndex(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient))
		return Plugin_Continue;

	ResetTimers(iClient);
	return Plugin_Continue;
}

void Event_PlayerAction(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	if (!g_cvarEnable.BoolValue || !g_bReadyUpAvailable || !IsInReady())
		return;

	int iClient = GetClientOfUserId(hEvent.GetInt("attacker"));
	if (!IsValidClientIndex(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient))
		return;

	ResetTimers(iClient);
}

void Event_PlayerJump(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	if (!g_cvarEnable.BoolValue || !g_bReadyUpAvailable || !IsInReady())
		return;

	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!IsValidClientIndex(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient))
		return;

	ResetTimers(iClient);
}

void Event_PlayerTeam(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	if (!g_cvarEnable.BoolValue || !g_bReadyUpAvailable || !IsInReady())
		return;

	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!IsValidClientIndex(iClient) || !IsClientInGame(iClient) || IsFakeClient(iClient))
		return;

	ResetTimers(iClient);
}

void Event_OnPressed(const char[] sName, int iCaller, int iActivator, float fDelay)
{
	if (!g_cvarEnable.BoolValue || !g_bReadyUpAvailable || !IsInReady())
		return;

	if (!IsValidClientIndex(iActivator) || !IsClientInGame(iActivator) || IsFakeClient(iActivator))
		return;

	ResetTimers(iActivator);
}

public void OnClientPutInServer(int iClient)
{
	if (!g_cvarEnable.BoolValue || !g_bReadyUpAvailable || !IsInReady())
		return;

	if (IsFakeClient(iClient))
		return;

	g_iPlayerAFK[iClient] = g_cvarTime.IntValue;
}

public OnReadyUpInitiate()
{
	if (!g_cvarEnable.BoolValue)
		return;

	if (g_cvarReadyFooter.BoolValue)
	{
		char sBuffer[64];
		Format(sBuffer, sizeof(sBuffer), "%T", "Footer", LANG_SERVER, g_cvarTime.IntValue);
		AddStringToReadyFooter("");
		AddStringToReadyFooter(sBuffer);
	}

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
			continue;

		L4DTeam Team = L4D_GetClientTeam(iClient);
		if (Team == L4DTeam_Spectator || Team == L4DTeam_Unassigned)
			continue;

		if (g_cvarDebug.BoolValue)
			CPrintToChatAll("%t Set timer to: {blue}%N{default} | {green}%d{default}", "Tag", iClient, g_cvarTime.IntValue);

		g_iPlayerAFK[iClient] = g_cvarTime.IntValue;
		GetClientAbsOrigin(iClient, g_fPlayerLastPos[iClient]);
		GetClientEyeAngles(iClient, g_fPlayerLastEyes[iClient]);
	}

	delete g_hStartTimerAFK;
	g_hStartTimerAFK = CreateTimer(1.0, Timer_CheckAFK, _, TIMER_REPEAT);
}

public OnRoundIsLive()
{
	if (g_cvarEnable.BoolValue)
		delete g_hStartTimerAFK;
}

/*****************************************************************
			P L U G I N   F U N C T I O N S
*****************************************************************/

Action Timer_CheckAFK(Handle timer)
{
	float fPos[3];
	float fEyes[3];
	bool  bIsAFK;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		L4DTeam Team = L4D_GetClientTeam(i);
		if (Team == L4DTeam_Spectator || Team == L4DTeam_Unassigned)
			continue;

		if (g_cvarPlayerIgnore.BoolValue && IsReady(i))
			continue;

		if (g_cvarShowTimer.BoolValue && g_iPlayerAFK[i] <= g_cvarShowTimer.IntValue)
			CPrintToChat(i, "%t %t", "Tag", "ShowTimer", g_iPlayerAFK[i]);

		GetClientAbsOrigin(i, fPos);
		GetClientEyeAngles(i, fEyes);

		bIsAFK = true;

		if (GetVectorDistance(fPos, g_fPlayerLastPos[i]) > 80.0)
			bIsAFK = false;

		if (bIsAFK)
		{
			if (fEyes[0] != g_fPlayerLastEyes[i][0] && fEyes[1] != g_fPlayerLastEyes[i][1])
				bIsAFK = false;
		}

		if (bIsAFK)
		{
			if (g_iPlayerAFK[i] > 0)
			{
				g_iPlayerAFK[i] = g_iPlayerAFK[i] - 1;

				if (g_iPlayerAFK[i] <= 0)
				{
					L4D_ChangeClientTeam(i, L4DTeam_Spectator);
					CPrintToChatAll("%t %t", "Tag", "MoveToSpec", i, g_iPlayerAFK[i]);
				}
			}
		}
		else
			ResetTimers(i);
	}
	return Plugin_Continue;
}

void ResetTimers(int iClient)
{
	L4DTeam Team = L4D_GetClientTeam(iClient);
	if (Team == L4DTeam_Spectator || Team == L4DTeam_Unassigned)
		return;

	g_iPlayerAFK[iClient] = g_cvarTime.IntValue;
	GetClientAbsOrigin(iClient, g_fPlayerLastPos[iClient]);
	GetClientEyeAngles(iClient, g_fPlayerLastEyes[iClient]);
}

/**
 * Check if the translation file exists
 *
 * @param translation	Translation name.
 * @noreturn
 */
stock void LoadTranslation(const char[] translation)
{
	char
		sPath[PLATFORM_MAX_PATH],
		sName[64];

	Format(sName, sizeof(sName), "translations/%s.txt", translation);
	BuildPath(Path_SM, sPath, sizeof(sPath), sName);
	if (!FileExists(sPath))
		SetFailState("Missing translation file %s.txt", translation);

	LoadTranslations(translation);
}

/**
 * Returns the clients team using L4DTeam.
 *
 * @param client		Player's index.
 * @return				Current L4DTeam of player.
 * @error				Invalid client index.
 */
stock L4DTeam L4D_GetClientTeam(int client)
{
	int team = GetClientTeam(client);
	return view_as<L4DTeam>(team);
}

/**
 * Changes the team of a client in Left 4 Dead.
 *
 * @param client The client index.
 * @param team The new team for the client.
 */
stock void L4D_ChangeClientTeam(int client, L4DTeam team)
{
	ChangeClientTeam(client, view_as<int>(team));
}

/**
 * Checks if a client index is valid.
 *
 * @param client The client index to check.
 */
stock bool IsValidClientIndex(int iClient)
{
	if (!iClient || iClient < 1 || iClient > MaxClients)
		return false;

	return true;
}