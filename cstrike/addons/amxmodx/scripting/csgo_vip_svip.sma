#include <amxmodx>
#include <reapi>
#include <csgomod>

#define PLUGIN	"CS:GO VIP & SVIP"
#define AUTHOR	"O'Zone & Czarintax"

#define ADMIN_FLAG_X (1<<23)

new Array:VIPs, Array:SVIPs, bool:used[MAX_PLAYERS + 1], bool:disabled, roundNum = 0,
	VIP, SVIP, smallMaps, freeType, freeEnabled, freeFrom, freeTo;

new const commandVIPs[][] = { "vips", "say /vips", "say_team /vips" };
new const commandSVIPs[][] = { "svips", "say /svips", "say_team /svips" };
new const commandVIPMotd[][] = { "vip", "say /vip", "say_team /vip" };
new const commandSVIPMotd[][] = { "svip", "say /svip", "say_team /svip", "say /supervip", "say_team /supervip" };

new disallowedWeapons[] = { CSW_XM1014, CSW_MAC10, CSW_AUG, CSW_M249, CSW_GALIL, CSW_AK47, CSW_M4A1, CSW_AWP,
	CSW_SG550, CSW_G3SG1, CSW_UMP45, CSW_MP5NAVY, CSW_FAMAS, CSW_SG552, CSW_TMP, CSW_P90, CSW_M3 };

enum { ammo_none, ammo_338magnum = 1, ammo_762nato, ammo_556natobox, ammo_556nato, ammo_buckshot, ammo_45acp,
	ammo_57mm, ammo_50ae, ammo_357sig, ammo_9mm, ammo_flashbang, ammo_hegrenade, ammo_smokegrenade, ammo_c4 };

enum _:{ PRIMARY = 1, SECONDARY, KNIFE, GRENADES, C4 };
enum _:{ FREE_NONE, FREE_HOURS, FREE_ALWAYS };
enum _:{ FREE_VIP, FREE_SVIP };

forward amxbans_admin_connect(id);

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);

	bind_pcvar_num(register_cvar("csgo_vip_svip_small_maps", "0"), smallMaps);
	bind_pcvar_num(register_cvar("csgo_vip_svip_free_enabled", "0"), freeEnabled);
	bind_pcvar_num(register_cvar("csgo_vip_svip_free_type", "0"), freeType);
	bind_pcvar_num(register_cvar("csgo_vip_svip_free_from", "23"), freeFrom);
	bind_pcvar_num(register_cvar("csgo_vip_svip_free_to", "9"), freeTo);

	for (new i; i < sizeof commandVIPs; i++) register_clcmd(commandVIPs[i], "show_vips");
	for (new i; i < sizeof commandSVIPs; i++) register_clcmd(commandSVIPs[i], "show_svips");
	for (new i; i < sizeof commandVIPMotd; i++) register_clcmd(commandVIPMotd[i], "show_vipmotd");
	for (new i; i < sizeof commandSVIPMotd; i++) register_clcmd(commandSVIPMotd[i], "show_svipmotd");

	register_clcmd("say_team", "handle_say");

	RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", .post = true);
	RegisterHookChain(RG_CSGameRules_RestartRound, "CSGameRules_RestartRound_Pre", .post = false);
	RegisterHookChain(RG_CBasePlayer_Killed, "CBasePlayer_Killed_Post", .post = true);

	register_message(get_user_msgid("ScoreAttrib"), "handle_status");
	register_message(get_user_msgid("AmmoX"), "handle_ammo");

	VIPs = ArrayCreate(32, 32);
	SVIPs = ArrayCreate(32, 32);
}

public plugin_natives()
{
	register_native("csgo_set_user_vip", "_csgo_set_user_vip", 1);
	register_native("csgo_get_user_vip", "_csgo_get_user_vip", 1);
	register_native("csgo_set_user_svip", "_csgo_set_user_svip", 1);
	register_native("csgo_get_user_svip", "_csgo_get_user_svip", 1);
}

public plugin_cfg()
	if (!smallMaps) check_map();

public plugin_end()
{
	ArrayDestroy(VIPs);
	ArrayDestroy(SVIPs);
}

public amxbans_admin_connect(id)
	client_authorized_post(id);


public client_authorized(id)
	client_authorized_post(id);

public client_authorized_post(id)
{
	rem_bit(id, VIP);
	rem_bit(id, SVIP);

	new currentTime[3], hour, bool:freeVip = freeEnabled == FREE_ALWAYS;

	if (!freeVip && freeEnabled == FREE_HOURS) {
		get_time("%H", currentTime, charsmax(currentTime));

		hour = str_to_num(currentTime);

		if (freeFrom >= freeTo && (hour >= freeFrom || hour < freeTo)) {
			freeVip = true;
		} else if (freeFrom < freeTo && (hour >= freeFrom && hour < freeTo)) {
			freeVip = true;
		}
	}

	if (get_user_flags(id) & ADMIN_LEVEL_H || get_user_flags(id) & ADMIN_FLAG_X || freeVip) {
		set_bit(id, VIP);

		new playerName[32], tempName[32], size = ArraySize(VIPs), bool:found;

		get_user_name(id, playerName, charsmax(playerName));

		for (new i = 0; i < size; i++) {
			ArrayGetString(VIPs, i, tempName, charsmax(tempName));

			if (equal(playerName, tempName)) found = true;
		}

		if (!found) ArrayPushString(VIPs, playerName);

		if (get_user_flags(id) & ADMIN_FLAG_X || freeType == FREE_SVIP) {
			set_bit(id, SVIP);

			new playerName[32], tempName[32], size = ArraySize(SVIPs);

			get_user_name(id, playerName, charsmax(playerName));

			for (new i = 0; i < size; i++) {
				ArrayGetString(SVIPs, i, tempName, charsmax(tempName));

				if (equal(playerName, tempName)) return PLUGIN_CONTINUE;
			}

			ArrayPushString(SVIPs, playerName);
		}
	}

	return PLUGIN_CONTINUE;
}

public client_disconnected(id)
{
	if (get_bit(id, VIP)) {
		rem_bit(id, VIP);

		new playerName[32], tempName[32], size = ArraySize(VIPs);

		get_user_name(id, playerName, charsmax(playerName));

		for (new i = 0; i < size; i++) {
			ArrayGetString(VIPs, i, tempName, charsmax(tempName));

			if (equal(playerName, tempName)) {
				ArrayDeleteItem(VIPs, i);

				break;
			}
		}
	}

	if (get_bit(id, SVIP)) {
		rem_bit(id, SVIP);

		new playerName[32], tempName[32], size = ArraySize(SVIPs);

		get_user_name(id, playerName, charsmax(playerName));

		for (new i = 0; i < size; i++) {
			ArrayGetString(SVIPs, i, tempName, charsmax(tempName));

			if (equal(playerName, tempName)) {
				ArrayDeleteItem(SVIPs, i);

				break;
			}
		}
	}

	return PLUGIN_CONTINUE;
}

public client_infochanged(id)
{
	if (get_bit(id, VIP)) {
		new playerName[32], newName[32], tempName[32], size = ArraySize(VIPs);

		get_user_info(id, "name", newName, charsmax(newName));
		get_user_name(id, playerName, charsmax(playerName));

		if (playerName[0] && !equal(playerName, newName)) {
			ArrayPushString(VIPs, newName);

			for (new i = 0; i < size; i++) {
				ArrayGetString(VIPs, i, tempName, charsmax(tempName));

				if (equal(playerName, tempName)) {
					ArrayDeleteItem(VIPs, i);

					break;
				}
			}
		}
	}

	if (get_bit(id, SVIP)) {
		new playerName[32], newName[32], tempName[32], size = ArraySize(SVIPs);

		get_user_info(id, "name", newName,charsmax(newName));
		get_user_name(id, playerName, charsmax(playerName));

		if (playerName[0] && !equal(playerName, newName)) {
			ArrayPushString(SVIPs, newName);

			for (new i = 0; i < size; i++) {
				ArrayGetString(SVIPs, i, tempName, charsmax(tempName));

				if (equal(playerName, tempName)) {
					ArrayDeleteItem(SVIPs, i);

					break;
				}
			}
		}
	}
}

public show_vipmotd(id)
{
	new motdTitle[32], motdFile[32];

	formatex(motdTitle, charsmax(motdTitle), "%L", id, "CSGO_VIP_VIP_MOTD_TITLE");
	formatex(motdFile, charsmax(motdFile), "%L", id, "CSGO_VIP_VIP_MOTD_FILE");

	show_motd(id, motdFile, motdTitle);
}

public show_svipmotd(id)
{
	new motdTitle[32], motdFile[32];

	formatex(motdTitle, charsmax(motdTitle), "%L", id, "CSGO_VIP_SVIP_MOTD_TITLE");
	formatex(motdFile, charsmax(motdFile), "%L", id, "CSGO_VIP_SVIP_MOTD_FILE");

	show_motd(id, motdFile, motdTitle);
}

public CSGameRules_RestartRound_Pre()
{
	if(!get_member_game(m_bCompleteReset))
		++roundNum;
	else
		roundNum = 1;
}

public csgo_user_login(id)
	CBasePlayer_Spawn_Post(id);

public CBasePlayer_Spawn_Post(id)
{
	if (disabled || !csgo_check_account(id))
		return HC_CONTINUE;

	remove_task(id);
	client_authorized_post(id);

	if (!is_user_alive(id) || !is_entity(id) || !get_bit(id, VIP))
		return HC_CONTINUE;

	if (get_user_team(id) == 2) rg_give_defusekit(id, true);
	
	if (roundNum >= 2) {
		rg_give_item(id, "weapon_deagle", GT_REPLACE);
		rg_set_user_bpammo(id, WEAPON_DEAGLE, 35);
		rg_give_item(id, "weapon_hegrenade");

		if (get_bit(id, SVIP)) {
			rg_give_item(id, "weapon_flashbang");
			rg_give_item(id, "weapon_flashbang");
		}

		rg_set_user_armor(id, 100, ARMOR_VESTHELM);
	} else {
		vip_menu_pistol(id);
	}

	if (roundNum >= 3) vip_menu(id);

	return HC_CONTINUE;
}

public vip_menu(id)
{
	used[id] = false;

	set_task(15.0, "close_vip_menu", id);

	new menu, title[64];

	formatex(title, charsmax(title), ^"%L", id, get_bit(id, SVIP) ? "CSGO_VIP_MENU_WEAPONS_SVIP" : "CSGO_VIP_MENU_WEAPONS_VIP");
	menu = menu_create(title, "vip_menu_handle");

	formatex(title, charsmax(title), ^"^5%L", id, "CSGO_VIP_MENU_M4A1");
	menu_additem(menu, title);

	formatex(title, charsmax(title), ^"^1%L", id, "CSGO_VIP_MENU_AK47");
	menu_additem(menu, title);

	if (get_bit(id, SVIP)) {
		formatex(title, charsmax(title), ^"^2%L", id, "CSGO_VIP_MENU_AWP");
		menu_additem(menu, title);
	}

	formatex(title, charsmax(title), ^"%L", id, "CSGO_MENU_EXIT");
	menu_setprop(menu, MPROP_EXITNAME, title);

	menu_display(id, menu);
}

public vip_menu_handle(id, menu, item)
{
	if (!is_entity(id) || !is_user_alive(id) || used[id] || item == MENU_EXIT) {
		menu_destroy(menu);
		
		remove_task(id);

		return PLUGIN_HANDLED;
	}

	used[id] = true;

	switch (item) {
		case 0: {
			rg_give_item(id, "weapon_m4a1", GT_REPLACE)
			rg_set_user_bpammo(id, WEAPON_M4A1, 90);

			client_print(id, print_center, "%L", id, "CSGO_VIP_M4A1");
		} case 1: {
			rg_give_item(id, "weapon_ak47", GT_REPLACE);
			rg_set_user_bpammo(id, WEAPON_AK47, 90);

			client_print(id, print_center, "%L", id, "CSGO_VIP_AK47");
		} case 2: {
			rg_give_item(id, "weapon_awp", GT_REPLACE);
			rg_set_user_bpammo(id, WEAPON_AWP, 30);

			client_print(id, print_center, "%L", id, "CSGO_VIP_AWP");
		}
	}

	remove_task(id);

	menu_destroy(menu);

	return PLUGIN_HANDLED;
}

public close_vip_menu(id)
{
	if (used[id] || !is_user_alive(id) || !is_entity(id))
		return PLUGIN_CONTINUE;

	if (!check_weapons(id)) {
		if (get_bit(id, SVIP)) {
			client_print(id, print_chat, ^"^3[^2SVIP^3] %L", id, "CSGO_VIP_RANDOM_WEAPONS_SVIP");
		} else {
			client_print(id, print_chat, ^"^3[^2VIP^3] %L", id, "CSGO_VIP_RANDOM_WEAPONS_VIP");
		}

		used[id] = true;

		new random = random_num(0, get_bit(id, SVIP) ? 2 : 1);

		switch (random) {
			case 0: {
				rg_give_item(id, "weapon_m4a1", GT_REPLACE);
				rg_set_user_bpammo(id, WEAPON_M4A1, 90);

				client_print(id, print_center, "%L", id, "CSGO_VIP_M4A1");
			} case 1: {
				rg_give_item(id, "weapon_ak47", GT_REPLACE);
				rg_set_user_bpammo(id, WEAPON_AK47, 90);

				client_print(id, print_center, "%L", id, "CSGO_VIP_AK47");
			} case 2: {
				rg_give_item(id, "weapon_awp", GT_REPLACE);
				rg_set_user_bpammo(id, WEAPON_AWP, 30);

				client_print(id, print_center, "%L", id, "CSGO_VIP_AWP");
			}
		}
	}

	return PLUGIN_CONTINUE;
}

public vip_menu_pistol(id)
{
	used[id] = false;

	set_task(15.0, "close_vip_menu_pistol", id);

	new menu, title[64];

	formatex(title, charsmax(title), "%L", id, get_bit(id, SVIP) ? ^"CSGO_VIP_MENU_PISTOL_SVIP" : ^"CSGO_VIP_MENU_PISTOL_VIP");
	menu = menu_create(title, "vip_menu_pistol_handle");

	formatex(title, charsmax(title), "%L", id, "CSGO_VIP_MENU_DEAGLE");
	menu_additem(menu, title);

	formatex(title, charsmax(title), "%L", id, "CSGO_VIP_MENU_USP");
	menu_additem(menu, title);

	formatex(title, charsmax(title), "%L", id, "CSGO_VIP_MENU_GLOCK");
	menu_additem(menu, title);

	formatex(title, charsmax(title), "%L", id, "CSGO_MENU_EXIT");
	menu_setprop(menu, MPROP_EXITNAME, title);

	menu_display(id, menu);
}

public vip_menu_pistol_handle(id, menu, item)
{
	if (!is_entity(id) || !is_user_alive(id) || used[id] || item == MENU_EXIT) {
		menu_destroy(menu);
		
		remove_task(id);

		return PLUGIN_HANDLED;
	}

	used[id] = true;

	switch (item) {
		case 0: {
			rg_give_item(id, "weapon_deagle", GT_REPLACE);
			rg_set_user_bpammo(id, WEAPON_DEAGLE, 35);
			
			client_print(id, print_center, "%L", id, "CSGO_VIP_DEAGLE");
		} case 1: {
			rg_give_item(id, "weapon_usp", GT_REPLACE);
			rg_set_user_bpammo(id, WEAPON_USP, 100);

			client_print(id, print_center, "%L", id, "CSGO_VIP_USP");
		} case 2: {
			rg_give_item(id, "weapon_glock18", GT_REPLACE);
			rg_set_user_bpammo(id, WEAPON_GLOCK18, 120);

			client_print(id, print_center, "%L", id, "CSGO_VIP_GLOCK");
		}
	}

	remove_task(id);

	menu_destroy(menu);

	return PLUGIN_HANDLED;
}

public close_vip_menu_pistol(id)
{
	if (used[id] || !is_user_alive(id) || !is_entity(id))
		return PLUGIN_CONTINUE;

	if (!check_weapons(id)) {
		if (get_bit(id, SVIP)) {
			client_print(id, print_chat, ^"^3[^2SVIP^3] %L", id, "CSGO_VIP_RANDOM_PISTOL_SVIP");
		} else {
			client_print(id, print_chat, ^"^3[^2VIP^3] %L", id, "CSGO_VIP_RANDOM_PISTOL_VIP");
		}

		used[id] = true;

		new random = random_num(0, 2);

		switch (random) {
			case 0: {
				rg_give_item(id, "weapon_deagle", GT_REPLACE);
				rg_set_user_bpammo(id, WEAPON_DEAGLE, 35);

				client_print(id, print_center, "%L", id, "CSGO_VIP_DEAGLE");
			} case 1: {
				rg_give_item(id, "weapon_usp", GT_REPLACE);
				rg_set_user_bpammo(id, WEAPON_USP, 100);

				client_print(id, print_center, "%L", id, "CSGO_VIP_USP");
			} case 2: {
				rg_give_item(id, "weapon_glock18", GT_REPLACE);
				rg_set_user_bpammo(id, WEAPON_GLOCK18, 120);

				client_print(id, print_center, "%L", id, "CSGO_VIP_GLOCK");
			}
		}
	}

	return PLUGIN_CONTINUE;
}

public CBasePlayer_Killed_Post(const victim, killer, iGib)
{
	if (!disabled) return HC_CONTINUE;
	
	if (!is_user_connected(killer)) return HC_CONTINUE;
	
	if (victim == killer || get_member(victim, m_bKilledByBomb)) return HC_CONTINUE;
	
	//if (get_member(victim, m_iTeam) == get_member(killer, m_iTeam)) return HC_CONTINUE; // FFA
	
	if (!get_bit(killer, VIP)) return HC_CONTINUE;
	
	static Float:killer_HP, Float:HP_HS, Float:HP_BODY;
	killer_HP = get_entvar(killer, var_health);
	HP_HS = 10.0;
	HP_BODY = 5.0;
   
	if(!(killer_HP < 100.0)) return HC_CONTINUE;
		
	if (get_member(victim, m_bHeadshotKilled)) {
		set_hudmessage(38, 218, 116, 0.50, 0.35, 0, 0.0, 1.0, 0.0, 0.0);
		show_hudmessage(killer, "%L", killer, "CSGO_VIP_KILL_HS", get_bit(killer, SVIP) ? (floatround(HP_HS) + 5) : floatround(HP_HS));

		set_entvar(killer, var_health, ((killer_HP) > 100.00) ? (get_bit(killer, SVIP) ? (HP_HS + 5.0) : HP_HS) : killer_HP);

		rg_add_account(killer, 350, AS_ADD);
	} else	{
		set_hudmessage(255, 212, 0, 0.50, 0.31, 0, 0.0, 1.0, 0.0, 0.0);
		show_hudmessage(killer, "%L", killer, "CSGO_VIP_KILL", get_bit(killer, SVIP) ? (floatround(HP_BODY) + 5) : floatround(HP_BODY));

		set_entvar(killer, var_health, ((killer_HP) > 100.00) ? (get_bit(killer, SVIP) ? (HP_BODY + 5.0) : HP_BODY) : killer_HP);

		rg_add_account(killer, 200, AS_ADD);
	}
	
	return HC_CONTINUE;
}

public show_vips(id)
{
	new playerName[32], tempMessage[190], message[190], size = ArraySize(VIPs);

	for (new i = 0; i < size; i++) {
		ArrayGetString(VIPs, i, playerName, charsmax(playerName));

		add(tempMessage, charsmax(tempMessage), playerName);

		if (i == size - 1) add(tempMessage, charsmax(tempMessage), ".");
		else add(tempMessage, charsmax(tempMessage), ^", ^7");
	}

	formatex(message, charsmax(message), tempMessage);

	client_print(id, print_chat, ^"%s", message);

	return PLUGIN_CONTINUE;
}

public show_svips(id)
{
	new playerName[32], tempMessage[190], message[190], size = ArraySize(SVIPs);

	for (new i = 0; i < size; i++) {
		ArrayGetString(SVIPs, i, playerName, charsmax(playerName));

		add(tempMessage, charsmax(tempMessage), playerName);

		if (i == size - 1) add(tempMessage, charsmax(tempMessage), ".");
		else add(tempMessage, charsmax(tempMessage), ^", ^7");
	}

	formatex(message, charsmax(message), tempMessage);

	client_print(id, print_chat, ^"%s", message);

	return PLUGIN_CONTINUE;
}

public handle_status()
{
	new id = get_msg_arg_int(1);

	if (is_user_alive(id) && (get_bit(id, VIP) || get_bit(id, SVIP))) {
		set_msg_arg_int(2, ARG_BYTE, get_msg_arg_int(2) | 4);
	}
}

public handle_say(id)
{
	if (get_bit(id, VIP)) {
		new text[190], message[190];

		read_args(text, charsmax(text));
		remove_quotes(text);

		if (text[0] == '*' && text[1]) {
			formatex(message, charsmax(message), "^3(VIP CHAT) ^7%n: ^3%s", text[1]);

			if (is_user_alive(id)) {
				for (new i = 1; i <= MAX_PLAYERS; i++) {
					if (is_user_alive(i) && get_bit(i, VIP)) client_print(i, print_chat, ^"%s", message);
				}
			}
			else {
				for (new i = 1; i <= MAX_PLAYERS; i++) {
					if (!is_user_alive(i) && get_bit(i, VIP)) client_print(i, print_chat, ^"%s", message);
				}
			}

			return PLUGIN_HANDLED_MAIN;
		}
	}

	return PLUGIN_CONTINUE;
}

public handle_ammo(iMsgId, iMsgDest, id)
{
	if (!get_bit(id, SVIP))
		return PLUGIN_CONTINUE;
	
	new iWeapon = get_user_weapon(id);

	if(iWeapon && iWeapon != CSW_KNIFE && iWeapon != CSW_HEGRENADE && iWeapon != CSW_FLASHBANG && iWeapon != CSW_SMOKEGRENADE)
		rg_set_user_bpammo(id, any:iWeapon, rg_get_weapon_info(iWeapon, WI_MAX_ROUNDS));
	
	return PLUGIN_CONTINUE;
}

stock bool:check_weapons(id)
{
	new weapons[32], weapon, weaponsNum;

	weapon = get_user_weapons(id, weapons, weaponsNum);

	for (new i = 0; i < sizeof(disallowedWeapons); i++) {
		if (weapon & (1<<disallowedWeapons[i])) return true;
	}

	return false;
}

stock check_map()
{
	new mapPrefixes[][] = {
		"aim_",
		"awp_",
		"fy_" ,
		"cs_deagle5" ,
		"fun_allinone",
	};

	new mapName[32];

	get_mapname(mapName, charsmax(mapName));

	for (new i = 0; i < sizeof(mapPrefixes); i++) {
		if (containi(mapName, mapPrefixes[i]) != -1) disabled = true;
	}
}

public _csgo_get_user_vip(id)
	return get_bit(id, VIP);

public _csgo_get_user_svip(id)
	return get_bit(id, SVIP);

public _csgo_set_user_vip(id)
{
	if (get_user_flags(id) & ADMIN_LEVEL_H && !get_bit(id, VIP)) client_authorized_post(id);

	return PLUGIN_CONTINUE;
}

public _csgo_set_user_svip(id)
{
	if (get_user_flags(id) & ADMIN_FLAG_X && !get_bit(id, SVIP)) client_authorized_post(id);

	return PLUGIN_CONTINUE;
}
