#include <amxmodx>
#include <reapi>
#include <csgomod>

#define PLUGIN	"CS:GO Assist & Revenge"
#define AUTHOR	"O'Zone & Czarintax"

native csgo_add_kill(id);
native csgo_add_assist(id);

#define is_user_valid(%1)			(1 <= %1 <= MaxClients)

new playerName[MAX_PLAYERS + 1][32], playerRevenge[MAX_PLAYERS + 1], playerDamage[MAX_PLAYERS + 1][MAX_PLAYERS + 1];

new assistEnabled, revengeEnabled, assistDamage, Float:assistReward, Float:revengeReward, ForwardResult, assistForward;

new msgDeathMsg, msgScoreInfo;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
	
	bind_pcvar_num(create_cvar("csgo_assist_enabled", "1"), assistEnabled);
	bind_pcvar_num(create_cvar("csgo_revenge_enabled", "1"), revengeEnabled);
	bind_pcvar_num(create_cvar("csgo_assist_min_damage", "60"), assistDamage);
	bind_pcvar_float(create_cvar("csgo_assist_reward", "0.15"), assistReward);
	bind_pcvar_float(create_cvar("csgo_revenge_reward", "0.15"), revengeReward);
	
	msgDeathMsg = get_user_msgid("DeathMsg");
	msgScoreInfo = get_user_msgid("ScoreInfo");

	register_message(msgDeathMsg, "messageDeathMsg");

	register_event("Damage", "player_damage", "be", "2!0", "3=0", "4!0");
	register_event("DeathMsg", "player_die", "ae");

	RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", 1);
}

public client_putinserver(id)
{
	playerRevenge[id] = 0;

	for (new i = 1; i <= MAX_PLAYERS; i++) playerDamage[id][i] = 0;
}

public CBasePlayer_Spawn_Post(id)
{
	if (!is_user_alive(id)) return HC_CONTINUE;

	for (new i = 1; i <= MAX_PLAYERS; i++) playerDamage[id][i] = 0;

	return HC_CONTINUE;
}

public player_damage(victim)
{
	if (!assistEnabled) return PLUGIN_CONTINUE;
	
	if (!is_user_valid(victim)) return PLUGIN_CONTINUE;
	
	new attacker = get_user_attacker(victim);

	if (!is_user_valid(attacker)) return PLUGIN_CONTINUE;

	playerDamage[attacker][victim] += read_data(2);

	return PLUGIN_CONTINUE;
}

public player_die()
{
	if (!assistEnabled) return PLUGIN_CONTINUE;
	
	new victim = read_data(2), killer = read_data(1), hs = read_data(3);
	new weapon[24];
	read_data(4, weapon, charsmax(weapon));
	
	if(!is_user_valid(victim)) {
		do_deathmsg(killer, victim, hs, weapon);
		
		return PLUGIN_CONTINUE;
	}
	
	if(!is_user_valid(killer)) {
		do_deathmsg(killer, victim, hs, weapon);
		
		return PLUGIN_CONTINUE;
	}

	playerRevenge[victim] = killer;

	if (killer != victim && get_member(victim, m_iTeam) != get_member(killer, m_iTeam)) {
		if (playerRevenge[killer] == victim && revengeEnabled) {
			playerRevenge[killer] = 0;

			ExecuteForward(assistForward, ForwardResult, killer, victim);
			
			message_begin(MSG_ALL, msgScoreInfo);
			write_byte(killer);
			write_short(floatround(Float:get_entvar(killer, var_frags)));
			write_short(get_member(killer, m_iDeaths));
			write_short(0);
			write_short(get_member(killer, m_iTeam));
			message_end();
			
			rg_add_account(killer, 300);

			new victimName[32];
			get_user_name(victim, victimName, charsmax(victimName));

			client_print(killer, print_chat, ^"%s %L", CHAT_PREFIX, killer, "CSGO_REVENGE_CHAT", victimName);

			csgo_add_money(killer, revengeReward);
			csgo_add_kill(killer);
		}
		
		new assistant = 0, damage = 0;

		for (new i = 1; i <= MAX_PLAYERS; i++) {
			if (i != killer && is_user_connected(i) && get_member(i, m_iTeam) == get_member(killer, m_iTeam) && playerDamage[i][victim] >= assistDamage && playerDamage[i][victim] > damage) {
				assistant = i;
				damage = playerDamage[i][victim];
			}

			playerDamage[i][victim] = 0;
		}

		if (assistant > 0 && damage > assistDamage) {
			set_entvar(assistant, var_frags, Float:get_entvar(assistant, var_frags) + 1.0);
				
			message_begin(MSG_ALL, msgScoreInfo);
			write_byte(assistant);
			write_short(floatround(Float:get_entvar(assistant, var_frags)));
			write_short(get_member(assistant, m_iDeaths));
			write_short(0);
			write_short(get_member(assistant, m_iTeam));
			message_end();

			rg_add_account(assistant, 300);

			new killerName[32], assistantName[32], tempName[32], weaponLong[24];
			get_entvar(killer, var_netname, killerName, charsmax(killerName));
			get_entvar(assistant, var_netname, assistantName, charsmax(assistantName));
			
			playerName[killer] = killerName;
			
			if(strlen(killerName) + strlen(assistantName) > 28) {
				formatex(tempName, charsmax(tempName), ^"%.14s ^7+%s %.14s", killerName, get_member(assistant, m_iTeam) == TEAM_TERRORIST ? ^"^1" : ^"^5", assistantName);
			} else {
				formatex(tempName, charsmax(tempName), ^"%s ^7+%s %s", killerName, get_member(assistant, m_iTeam) == TEAM_TERRORIST ? ^"^1" : ^"^5", assistantName);
			}

			set_user_info(killer, "name", tempName);

			if(equali(weapon, "grenade"))
				weaponLong = "weapon_hegrenade";
			else
				formatex(weaponLong, charsmax(weaponLong), "weapon_%s", weapon);

			new args[4];
			args[0] = victim;
			args[1] = killer;
			args[2] = hs;
			args[3] = get_weaponid(weaponLong);
			
			set_task(0.2, "player_die_post", 0, args, 4);
			
			csgo_add_money(assistant, assistReward);
			csgo_add_assist(assistant);
		}
		else if(assistEnabled)
			do_deathmsg(killer, victim, hs, weapon);
	}
	else if(assistEnabled)
		do_deathmsg(killer, victim, hs, weapon);

	return PLUGIN_CONTINUE;
}

public player_die_post(arg[])
{
	new weapon[24];
	new killer = arg[1];

	get_weaponname(arg[3], weapon, charsmax(weapon));
	replace(weapon, charsmax(weapon), "weapon_", "");
	
	if(equali(weapon, "hegrenade"))
		weapon = "grenade";

	do_deathmsg(killer, arg[0], arg[2], weapon);

	set_user_info(killer, "name", playerName[killer]);

	return PLUGIN_CONTINUE;
}
	
public messageDeathMsg() 
	return assistEnabled ? PLUGIN_HANDLED : PLUGIN_CONTINUE;

stock do_deathmsg(killer, victim, hs, const weapon[])
{
	message_begin(MSG_ALL, msgDeathMsg);
	write_byte(killer);
	write_byte(victim);
	write_byte(hs);
	write_string(weapon);
	message_end();
}
