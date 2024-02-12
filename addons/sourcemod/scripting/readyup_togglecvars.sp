#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <readyup>

#define PLUGIN_VERSION "1.4"

public Plugin myinfo = 
{
	name = "[L4D2] Ready-Up Toggle Cvars",
	author = "Forgetest",
	description = "Customize your own Ready-Up state.",
	version = PLUGIN_VERSION,
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
};

enum struct CvarValue
{
	char on[128];
	char off[128];
}
StringMap g_smToggleCvars;

public void OnPluginStart()
{
	g_smToggleCvars = new StringMap();
	
	RegServerCmd("sm_readyup_add_togglecvars", Cmd_AddToggleCvars);
	RegServerCmd("sm_readyup_remove_togglecvars", Cmd_RemoveToggleCvars);
	RegServerCmd("sm_readyup_clear_togglecvars", Cmd_ClearToggleCvars);
}

public void OnPluginEnd()
{
	OnRoundIsLive();
}

Action Cmd_AddToggleCvars(int args)
{
	if (args != 3)
	{
		PrintToServer("Usage: sm_readyup_add_togglecvars <cvar> <value_on> <value_off>");
		return Plugin_Handled;
	}
	
	char sCvar[128];
	GetCmdArg(1, sCvar, sizeof(sCvar));
	StripQuotes(sCvar);
	
	CvarValue v;
	GetCmdArg(2, v.on, sizeof(v.on));
	GetCmdArg(3, v.off, sizeof(v.off));
	StripQuotes(v.on);
	StripQuotes(v.off);
	
	g_smToggleCvars.SetArray(sCvar, v, sizeof(v));
	PrintToServer("[ReadyUp ToggleCvars] Added: %s <%s|%s>", sCvar, v.on, v.off);
	
	return Plugin_Handled;
}

Action Cmd_RemoveToggleCvars(int args)
{
	if (args != 1)
	{
		PrintToServer("Usage: sm_readyup_remove_togglecvars <cvar>");
		return Plugin_Handled;
	}
	
	char sCvar[128];
	GetCmdArg(1, sCvar, sizeof(sCvar));
	StripQuotes(sCvar);
	RemoveToggleCvar(sCvar);
	
	return Plugin_Handled;
}

Action Cmd_ClearToggleCvars(int args)
{
	StringMapSnapshot ss = g_smToggleCvars.Snapshot();
	
	char sCvar[128];
	for (int i = 0; i < ss.Length; ++i)
	{
		ss.GetKey(i, sCvar, sizeof(sCvar));
		RemoveToggleCvar(sCvar);
	}
	PrintToServer("[ReadyUp ToggleCvars] Cleared all entries.");
	
	delete ss;
	
	return Plugin_Handled;
}

void RemoveToggleCvar(const char[] sCvar)
{
	if (g_smToggleCvars.Remove(sCvar))
	{
		PrintToServer("[ReadyUp ToggleCvars] Removed: %s", sCvar);
	}
}

public void OnReadyUpInitiate()
{
	StringMapSnapshot ss = g_smToggleCvars.Snapshot();
	
	char sCvar[128];
	CvarValue v;
	ConVar cvar;
	for (int i = 0; i < ss.Length; ++i)
	{
		ss.GetKey(i, sCvar, sizeof(sCvar));
		if ((cvar = FindConVar(sCvar)) != null)
		{
			if (g_smToggleCvars.GetArray(sCvar, v, sizeof(v)))
			{
				cvar.SetString(v.on);
			}
		}
	}
	
	delete ss;
}

public void OnRoundIsLive()
{
	StringMapSnapshot ss = g_smToggleCvars.Snapshot();
	
	char sCvar[128];
	CvarValue v;
	ConVar cvar;
	for (int i = 0; i < ss.Length; ++i)
	{
		ss.GetKey(i, sCvar, sizeof(sCvar));
		if ((cvar = FindConVar(sCvar)) != null)
		{
			if (g_smToggleCvars.GetArray(sCvar, v, sizeof(v)))
			{
				cvar.SetString(v.off);
			}
		}
	}
	
	delete ss;
}