#include <amxmodx>
#include <sqlx>
#include <reapi>
#include <csgomod>

#define PLUGIN	"CS:GO Accounts"
#define AUTHOR	"O'Zone"

#define TASK_PASSWORD   1945
#define TASK_LOAD       2491

enum _:playerInfo { STATUS, FAILS, PASSWORD[34], TEMP_PASSWORD[34], NAME[32], SAFE_NAME[64], AUTH_ID[65] };
enum _:status { NOT_REGISTERED, NOT_LOGGED, LOGGED, GUEST };
enum _:queries { UPDATE, INSERT, DELETE };

new const commandAccount[][] = { "password", "account", "say /password", "say_team /password", "say /account", "say_team /account" };

new playerData[MAX_PLAYERS + 1][playerInfo], setinfo[16], Handle:sql, bool:sqlConnected, dataLoaded, saveType,
	autoLogin, accountsEnabled, loginMaxTime, passwordMaxFails, passwordMinLength, blockMovement, forwardResult, loginForward, registerForward;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);

	for (new i; i < sizeof commandAccount; i++) register_clcmd(commandAccount[i], "account_menu");

	bind_pcvar_num(get_cvar_pointer("csgo_save_type"), saveType);
	bind_pcvar_num(create_cvar("csgo_accounts_enabled", "1"), accountsEnabled);
	bind_pcvar_num(create_cvar("csgo_accounts_login_max_time", "60"), loginMaxTime);
	bind_pcvar_num(create_cvar("csgo_accounts_password_max_fails", "3"), passwordMaxFails);
	bind_pcvar_num(create_cvar("csgo_accounts_password_min_length", "5"), passwordMinLength);
	bind_pcvar_num(create_cvar("csgo_accounts_block_movement", "1"), blockMovement);
	bind_pcvar_string(create_cvar("csgo_accounts_setinfo", "csgopass"), setinfo, charsmax(setinfo));

	register_clcmd("ENTER_YOUR_PASSWORD", "login_account");
	register_clcmd("ENTER_SELECTED_PASSWORD", "register_step_one");
	register_clcmd("REPEAT_SELECTED_PASSWORD", "register_step_two");
	register_clcmd("ENTER_CURRENT_PASSWORD", "change_step_one");
	register_clcmd("ENTER_NEW_PASSWORD", "change_step_two");
	register_clcmd("REPEAT_NEW_PASSWORD", "change_step_three");
	register_clcmd("ENTER_YOUR_CURRENT_PASSWORD", "delete_account");

	//RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", 1);
	
	RegisterHookChain(RG_ShowVGUIMenu, "@ShowVGUIMenu_Pre", .post = false);
	RegisterHookChain(RG_HandleMenu_ChooseTeam, "@HandleMenu_ChooseTeam_Pre", false);

	loginForward = CreateMultiForward("csgo_user_login", ET_IGNORE, FP_CELL);
	registerForward = CreateMultiForward("csgo_user_register", ET_IGNORE, FP_CELL);
}

public plugin_natives()
	register_native("csgo_check_account", "_csgo_check_account", 1);

public plugin_cfg()
	set_task(0.1, "sql_init");

public plugin_end()
	SQL_FreeHandle(sql);

public csgo_reset_data()
{
	for (new i = 1; i <= MAX_PLAYERS; i++) {
		rem_bit(i, dataLoaded);

		playerData[i][STATUS] = NOT_REGISTERED;
	}

	sqlConnected = false;

	new tempData[32];

	formatex(tempData, charsmax(tempData), "DROP TABLE `csgo_accounts`;");

	SQL_ThreadQuery(sql, "ignore_handle", tempData);
}

public client_connect(id)
{
	playerData[id][PASSWORD] = "";
	playerData[id][STATUS] = NOT_REGISTERED;
	playerData[id][FAILS] = 0;

	rem_bit(id, dataLoaded);
	rem_bit(id, autoLogin);

	if (is_user_bot(id) || is_user_hltv(id) || !accountsEnabled) return;

	get_user_authid(id, playerData[id][AUTH_ID], charsmax(playerData[][AUTH_ID]));
	get_user_name(id, playerData[id][NAME], charsmax(playerData[][NAME]));

	mysql_escape_string(playerData[id][NAME], playerData[id][SAFE_NAME], charsmax(playerData[][SAFE_NAME]));

	set_task(0.1, "load_account", id + TASK_LOAD);
}

public client_disconnected(id)
{
	remove_task(id + TASK_PASSWORD);
	remove_task(id + TASK_LOAD);
	remove_task(id);
}

@ShowVGUIMenu_Pre(id, VGUIMenu:menuType, bitsSlots, oldMenu[])
{
	if (menuType != VGUI_Menu_Team)
		return;

	if (get_member(id, m_iJoiningState) == JOINED)
		return;
		
	if (!accountsEnabled || !is_user_connected(id) || playerData[id][STATUS] >= LOGGED)
		return;
	
	set_member(id, m_bForceShowMenu, true);
	set_member_game(m_bSkipShowMenu, true);

	SetHookChainArg(3, ATYPE_INTEGER, 1023);
	SetHookChainArg(4, ATYPE_STRING, "\n");
	
	set_task(1.0, "account_menu", id);
}

@HandleMenu_ChooseTeam_Pre(id, key)
{
	if (!accountsEnabled || !is_user_connected(id) || playerData[id][STATUS] >= LOGGED)
		return HC_CONTINUE;

	SetHookChainReturn(ATYPE_INTEGER, false);
	return HC_SUPERCEDE;
}
/*
public CBasePlayer_Spawn_Post(id)
{
	if (!accountsEnabled || !is_user_alive(id) || playerData[id][STATUS] >= LOGGED)
		return HC_CONTINUE;

	account_menu(id);
	
	if (!accountsEnabled || !blockMovement || !is_user_alive(id) || is_user_bot(id) || playerData[id][STATUS] >= LOGGED)
		return HC_CONTINUE;

	set_entvar(id, var_flags, get_entvar(id, var_flags) | FL_FROZEN);
	
	return HC_CONTINUE;
}
*/
public kick_player(id)
{
	id -= TASK_PASSWORD;

	if (!is_user_connected(id)) return;

	new info[64];

	formatex(info, charsmax(info), "%L", id, "CSGO_ACCOUNTS_TIMEOUT", loginMaxTime);

	server_cmd("kick #%d ^"%s^"", get_user_userid(id), info);
}

public account_menu(id)
{
	if (!accountsEnabled || !is_user_connected(id))
		return PLUGIN_HANDLED;

	if (!get_bit(id, dataLoaded)) {
		remove_task(id);

		set_task(0.1, "account_menu", id);

		return PLUGIN_HANDLED;
	}

	if (playerData[id][STATUS] <= NOT_LOGGED && !task_exists(id + TASK_PASSWORD)) {
		set_task(float(loginMaxTime), "kick_player", id + TASK_PASSWORD);
	}

	new menuData[256], title[128];

	switch (playerData[id][STATUS]) {
		case NOT_REGISTERED: formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_STATUS_NOT_REGISTERED");
		case NOT_LOGGED: formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_STATUS_NOT_LOGGED_IN");
		case LOGGED: formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_STATUS_LOGGED_IN");
		case GUEST: formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_STATUS_GUEST");
	}

	formatex(menuData, charsmax(menuData), "%L", id, "CSGO_ACCOUNTS_MENU_TITLE", playerData[id][NAME], title);
	/*
	if ((playerData[id][STATUS] == NOT_LOGGED || playerData[id][STATUS] == LOGGED) && !get_bit(id, autoLogin)) {
		format(menuData, charsmax(menuData), "%L", id, "CSGO_ACCOUNTS_MENU_INFO", menuData, setinfo);
	}
	*/
	new menu = menu_create(menuData, "account_menu_handle"), callback = menu_makecallback("account_menu_callback");

	formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_LOGIN");
	menu_additem(menu, title, _, _, callback);

	formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_REGISTRATION");
	menu_additem(menu, title, _, _, callback);

	formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_PASSWORD_CHANGE");
	menu_additem(menu, title, _, _, callback);

	formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_DELETE");
	menu_additem(menu, title, _, _, callback);

	formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_LOGIN_GUEST");
	menu_additem(menu, title, _, _, callback);

	if (playerData[id][STATUS] >= LOGGED) {
		formatex(title, charsmax(title), "%L", id, "CSGO_MENU_EXIT");
		
		menu_setprop(menu, MPROP_EXITNAME, title);
	} else {
		menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
	}

	menu_display(id, menu);

	return PLUGIN_HANDLED;
}

public account_menu_callback(id, menu, item)
{
	switch (item) {
		case 0: return playerData[id][STATUS] == NOT_LOGGED ? ITEM_ENABLED : ITEM_DISABLED;
		case 1: return (playerData[id][STATUS] == NOT_REGISTERED || playerData[id][STATUS] == GUEST) ? ITEM_ENABLED : ITEM_DISABLED;
		case 2, 3 : return playerData[id][STATUS] == LOGGED ? ITEM_ENABLED : ITEM_DISABLED;
		case 4: return playerData[id][STATUS] == NOT_REGISTERED ? ITEM_ENABLED : ITEM_DISABLED;
	}

	return ITEM_ENABLED;
}

public account_menu_handle(id, menu, item)
{
	if (!is_user_connected(id))
		return PLUGIN_HANDLED;

	if (item == MENU_EXIT) {
		menu_destroy(menu);

		return PLUGIN_HANDLED;
	}

	switch (item) {
		case 0: {
			client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_LOGIN_PASSWORD");

			set_hudmessage(255, 128, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
			show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_LOGIN_PASSWORD");

			client_cmd(id, "messagemode ENTER_YOUR_PASSWORD");
		} case 1: {
			client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_SELECT_PASSWORD");

			set_hudmessage(255, 128, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
			show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_LOGIN_PASSWORD");

			client_cmd(id, "messagemode ENTER_SELECTED_PASSWORD");

			remove_task(id + TASK_PASSWORD);
		} case 2: {
			client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_ENTER_CURRENT_PASSWORD");

			set_hudmessage(255, 128, 0, 0.22, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
			show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_ENTER_CURRENT_PASSWORD");

			client_cmd(id, "messagemode ENTER_CURRENT_PASSWORD");
		} case 3: {
			client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_ENTER_CURRENT_PASSWORD");

			set_hudmessage(255, 128, 0, 0.22, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
			show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_ENTER_CURRENT_PASSWORD");

			client_cmd(id, "messagemode ENTER_YOUR_CURRENT_PASSWORD");
		} case 4: {
			client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_REGISTER_TO");

			set_hudmessage(0, 255, 0, -1.0, 0.9, 0, 0.0, 3.5, 0.0, 0.0);
			show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_REGISTER_TO");

			remove_task(id + TASK_PASSWORD);

			playerData[id][STATUS] = GUEST;

			if (is_user_alive(id)) {
				set_entvar(id, var_flags, get_entvar(id, var_flags) | ~FL_FROZEN);
			}
			
			engclient_cmd(id, "menuselect", "0");

			ExecuteForward(loginForward, forwardResult, id);
		}
	}

	menu_destroy(menu);

	return PLUGIN_HANDLED;
}

public login_account(id)
{
	if (!accountsEnabled || playerData[id][STATUS] != NOT_LOGGED || !get_bit(id, dataLoaded))
		return PLUGIN_HANDLED;

	new password[34], hash[34];

	read_args(password, charsmax(password));

	remove_quotes(password);
	
	hash_string(password, Hash_Md5, hash, charsmax(hash));

	if (!equal(playerData[id][PASSWORD], hash)) {
		if (++playerData[id][FAILS] >= passwordMaxFails) {
			new info[64];

			formatex(info, charsmax(info), "%L", id, "CSGO_ACCOUNTS_INVALID_PASSWORD");

			server_cmd("kick #%d ^"%s^"", get_user_userid(id), info);

			return PLUGIN_HANDLED;
		}

		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_WRONG_PASSWORD", playerData[id][FAILS], passwordMaxFails);

		set_hudmessage(255, 0, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);

		show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_WRONG_PASSWORD");

		account_menu(id);

		return PLUGIN_HANDLED;
	}

	playerData[id][STATUS] = LOGGED;
	playerData[id][FAILS] = 0;

	remove_task(id + TASK_PASSWORD);

	if (is_user_alive(id)) {
		set_entvar(id, var_flags, get_entvar(id, var_flags) | ~FL_FROZEN);
	}

	ExecuteForward(loginForward, forwardResult, id);

	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_LOGIN_SUCCESS");

	set_hudmessage(0, 255, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
	show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_LOGIN_SUCCESS");
	
	client_cmd(id, "setinfo _%s %s", setinfo, password);
	client_cmd(id, "seta ^"setu _%s^" %s", setinfo, password);
	
	engclient_cmd(id, "menuselect", "0");

	return PLUGIN_HANDLED;
}

public register_step_one(id)
{
	if (!accountsEnabled || (playerData[id][STATUS] != NOT_REGISTERED && playerData[id][STATUS] != GUEST) || !get_bit(id, dataLoaded)) return PLUGIN_HANDLED;

	new password[34];

	read_args(password, charsmax(password));
	remove_quotes(password);

	if (strlen(password) < passwordMinLength) {
		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_MIN_LENGTH", passwordMinLength);

		set_hudmessage(255, 0, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
		show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_MIN_LENGTH", passwordMinLength);

		account_menu(id);

		return PLUGIN_HANDLED;
	}

	copy(playerData[id][TEMP_PASSWORD], charsmax(playerData[][TEMP_PASSWORD]), password);

	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_REPEAT_PASSWORD");

	set_hudmessage(255, 128, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
	show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_REPEAT_PASSWORD");

	client_cmd(id, "messagemode REPEAT_SELECTED_PASSWORD");

	return PLUGIN_HANDLED;
}

public register_step_two(id)
{
	if (!accountsEnabled || (playerData[id][STATUS] != NOT_REGISTERED && playerData[id][STATUS] != GUEST) || !get_bit(id, dataLoaded)) return PLUGIN_HANDLED;

	new password[34];

	read_args(password, charsmax(password));
	remove_quotes(password);

	if (!equal(password, playerData[id][TEMP_PASSWORD])) {
		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_PASSWORD_DIFFER");

		set_hudmessage(255, 0, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
		show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_PASSWORD_DIFFER");

		account_menu(id);

		return PLUGIN_HANDLED;
	}

	new menuData[192], title[64];

	formatex(menuData, charsmax(menuData), "%L", id, "CSGO_ACCOUNTS_REGISTER_CONFIRM_TITLE", playerData[id][NAME], playerData[id][TEMP_PASSWORD]);

	new menu = menu_create(menuData, "register_confirmation_handle");

	formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_REGISTER_CONFIRM");
	menu_additem(menu, title);

	formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_REGISTER_CHANGE_PASSWORD");
	menu_additem(menu, title);

	formatex(title, charsmax(title), "%L", id, "CSGO_ACCOUNTS_REGISTER_CANCEL");
	menu_additem(menu, title);

	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);

	menu_display(id, menu);

	return PLUGIN_HANDLED;
}

public register_confirmation_handle(id, menu, item)
{
	if (!is_user_connected(id)) return PLUGIN_HANDLED;

	if (item == MENU_EXIT) {
		menu_destroy(menu);

		return PLUGIN_HANDLED;
	}

	menu_destroy(menu);

	switch (item) {
		case 0: {
			playerData[id][STATUS] = LOGGED;

			copy(playerData[id][PASSWORD], charsmax(playerData[][PASSWORD]), playerData[id][TEMP_PASSWORD]);

			account_query(id, INSERT);

			if (is_user_alive(id)) {
				set_entvar(id, var_flags, get_entvar(id, var_flags) | ~FL_FROZEN);
			}

			ExecuteForward(registerForward, forwardResult, id);

			set_hudmessage(0, 255, 0, -1.0, 0.9, 0, 0.0, 3.5, 0.0, 0.0);
			show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_REGISTER_SUCCESS");

			client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_REGISTER_SUCCESS");
			//client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_SETINFO_HELP", setinfo, playerData[id][PASSWORD]);

			client_cmd(id, "setinfo _%s %s", setinfo, playerData[id][PASSWORD]);
			client_cmd(id, "seta ^"setu _%s^" %s", setinfo, playerData[id][PASSWORD]);
			
			engclient_cmd(id, "menuselect", "0");
		} case 1: {
			client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_REGISTER_STARTED");

			set_hudmessage(255, 128, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
			show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_REGISTER_STARTED");

			client_cmd(id, "messagemode ENTER_SELECTED_PASSWORD");
		} case 2: {
			account_menu(id);
		}
	}

	return PLUGIN_HANDLED;
}

public change_step_one(id)
{
	if (!accountsEnabled || playerData[id][STATUS] != LOGGED || !get_bit(id, dataLoaded))
		return PLUGIN_HANDLED;

	new password[34], hash[34];

	read_args(password, charsmax(password));
	
	remove_quotes(password);
	
	hash_string(password, Hash_Md5, hash, charsmax(hash));

	if (!equal(playerData[id][PASSWORD], hash)) {
		if (++playerData[id][FAILS] >= passwordMaxFails) {
			new info[64];

			formatex(info, charsmax(info), "%L", id, "CSGO_ACCOUNTS_INVALID_PASSWORD");

			server_cmd("kick #%d ^"%s^"", get_user_userid(id), info);

			return PLUGIN_HANDLED;
		}

		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_WRONG_PASSWORD", playerData[id][FAILS], passwordMaxFails);

		set_hudmessage(255, 0, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
		show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_WRONG_PASSWORD");

		account_menu(id);

		return PLUGIN_HANDLED;
	}

	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_ENTER_NEW_PASSWORD");

	set_hudmessage(255, 128, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
	show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_ENTER_NEW_PASSWORD");

	client_cmd(id, "messagemode ENTER_NEW_PASSWORD");

	return PLUGIN_HANDLED;
}

public change_step_two(id)
{
	if (!accountsEnabled || playerData[id][STATUS] != LOGGED || !get_bit(id, dataLoaded))
		return PLUGIN_HANDLED;

	new password[34], hash[34];

	read_args(password, charsmax(password));
	
	remove_quotes(password);
	
	hash_string(password, Hash_Md5, hash, charsmax(hash));

	if (equal(playerData[id][PASSWORD], hash)) {
		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_NEW_MATCHES_OLD");

		set_hudmessage(255, 0, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
		show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_NEW_MATCHES_OLD");

		account_menu(id);

		return PLUGIN_HANDLED;
	}

	if (strlen(password) < passwordMinLength) {
		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_NEW_MIN_LENGTH", passwordMinLength);

		set_hudmessage(255, 0, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
		show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_NEW_MIN_LENGTH", passwordMinLength);

		account_menu(id);

		return PLUGIN_HANDLED;
	}

	copy(playerData[id][TEMP_PASSWORD], charsmax(playerData[][TEMP_PASSWORD]), password);

	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_REPEAT_NEW_PASSWORD");

	set_hudmessage(255, 128, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
	show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_REPEAT_NEW_PASSWORD");

	client_cmd(id, "messagemode REPEAT_NEW_PASSWORD");

	return PLUGIN_HANDLED;
}

public change_step_three(id)
{
	if (!accountsEnabled || playerData[id][STATUS] != LOGGED || !get_bit(id, dataLoaded))
		return PLUGIN_HANDLED;

	new password[34];

	read_args(password, charsmax(password));
	
	remove_quotes(password);

	if (!equal(password, playerData[id][TEMP_PASSWORD])) {
		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_PASSWORD_DIFFER");

		set_hudmessage(255, 0, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
		show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_PASSWORD_DIFFER");

		account_menu(id);

		return PLUGIN_HANDLED;
	}

	copy(playerData[id][PASSWORD], charsmax(playerData[][PASSWORD]), password);

	account_query(id, UPDATE);

	set_hudmessage(0, 255, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
	show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_PASSWORD_CHANGE_SUCCESS");

	client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_PASSWORD_CHANGE_SUCCESS");
	//client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_SETINFO_HELP", setinfo, playerData[id][PASSWORD]);

	client_cmd(id, "setinfo _%s %s", setinfo, playerData[id][PASSWORD]);
	client_cmd(id, "seta ^"setu _%s^" %s", setinfo, playerData[id][PASSWORD]);

	return PLUGIN_HANDLED;
}

public delete_account(id)
{
	if (!accountsEnabled || playerData[id][STATUS] != LOGGED || !get_bit(id, dataLoaded))
		return PLUGIN_HANDLED;

	new password[34], hash[34];

	read_args(password, charsmax(password));
	
	remove_quotes(password);
	
	hash_string(password, Hash_Md5, hash, charsmax(hash));

	if (!equal(playerData[id][PASSWORD], hash)) {
		if (++playerData[id][FAILS] >= passwordMaxFails) {
			new info[64];

			formatex(info, charsmax(info), "%L", id, "CSGO_ACCOUNTS_INVALID_PASSWORD");

			server_cmd("kick #%d ^"%s^"", get_user_userid(id), info);

			return PLUGIN_HANDLED;
		}

		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_WRONG_PASSWORD", playerData[id][FAILS], passwordMaxFails);

		set_hudmessage(255, 0, 0, 0.24, 0.07, 0, 0.0, 3.5, 0.0, 0.0);
		show_hudmessage(id, "%L", id, "CSGO_ACCOUNTS_HUD_WRONG_PASSWORD");

		account_menu(id);

		return PLUGIN_HANDLED;
	}

	new menuData[128], title[32];

	formatex(menuData, charsmax(menuData), "%L", id, "CSGO_ACCOUNTS_DELETE");

	new menu = menu_create(menuData, "delete_account_handle");

	formatex(title, charsmax(title), ^"^2%L", id, "CSGO_MENU_YES");
	menu_additem(menu, title);

	formatex(title, charsmax(title), ^"^3%L", id, "CSGO_MENU_NO");
	menu_additem(menu, title);

	formatex(title, charsmax(title), ^"^1%L", id, "CSGO_MENU_EXIT");
	menu_setprop(menu, MPROP_EXITNAME, title);

	menu_display(id, menu);

	return PLUGIN_HANDLED;
}

public delete_account_handle(id, menu, item)
{
	if (!is_user_connected(id))
		return PLUGIN_HANDLED;

	if (item == MENU_EXIT || item) {
		menu_destroy(menu);

		return PLUGIN_HANDLED;
	}

	menu_destroy(menu);

	account_query(id, DELETE);

	new info[128];

	client_print(id, print_console, "==================================");
	client_print(id, print_console, "==========%L==========", id, "CSGO_ACCOUNTS_CONSOLE_TITLE");
	client_print(id, print_console, "              %L", id, "CSGO_ACCOUNTS_CONSOLE_INFO", playerData[id][NAME]);
	client_print(id, print_console, "==================================");

	formatex(info, charsmax(info), "%L", id, "CSGO_ACCOUNTS_DELETED");

	server_cmd("kick #%d ^"%s^"", get_user_userid(id), info);

	return PLUGIN_CONTINUE;
}

public sql_init()
{
	new host[64], user[64], pass[64], db[64], error[256], errorNum;

	get_cvar_string("csgo_sql_host", host, charsmax(host));
	get_cvar_string("csgo_sql_user", user, charsmax(user));
	get_cvar_string("csgo_sql_pass", pass, charsmax(pass));
	get_cvar_string("csgo_sql_db", db, charsmax(db));

	sql = SQL_MakeDbTuple(host, user, pass, db);

	new Handle:connection = SQL_Connect(sql, errorNum, error, charsmax(error));

	if (errorNum) {
		log_to_file("csgo-error.log", "[CS:GO Accounts] Init SQL Error: %s (%i)", error, errorNum);

		SQL_FreeHandle(connection);

		return;
	}

	new queryData[192], bool:hasError;

	formatex(queryData, charsmax(queryData), "CREATE TABLE IF NOT EXISTS `csgo_accounts` (`name` VARCHAR(64), `authid` VARCHAR(65), `pass` VARCHAR(34), PRIMARY KEY(name, authid));");

	new Handle:query = SQL_PrepareQuery(connection, queryData);

	if (!SQL_Execute(query)) {
		SQL_QueryError(query, error, charsmax(error));

		log_to_file("csgo-error.log", "[CS:GO Accounts] Init SQL Error: %s", error);

		hasError = true;
	}

	SQL_FreeHandle(query);
	SQL_FreeHandle(connection);

	if (!hasError) sqlConnected = true;
}

public load_account(id)
{
	id -= TASK_LOAD;

	if (!sqlConnected) {
		set_task(1.0, "load_account", id + TASK_LOAD);

		return;
	}

	new queryData[128], tempId[1];

	tempId[0] = id;

	switch (saveType) {
		case SAVE_NAME: formatex(queryData, charsmax(queryData), "SELECT * FROM `csgo_accounts` WHERE name = ^"%s^" LIMIT 1;", playerData[id][SAFE_NAME]);
		case SAVE_AUTH_ID: formatex(queryData, charsmax(queryData), "SELECT * FROM `csgo_accounts` WHERE authid = ^"%s^" LIMIT 1;", playerData[id][AUTH_ID]);
	}

	SQL_ThreadQuery(sql, "load_account_handle", queryData, tempId, sizeof(tempId));
}

public load_account_handle(failState, Handle:query, error[], errorNum, tempId[], dataSize)
{
	new id = tempId[0];

	if (failState) {
		log_to_file("csgo-error.log", "[CS:GO Accounts] SQL Error: %s (%d)", error, errorNum);

		return;
	}

	if (SQL_MoreResults(query)) {
		SQL_ReadResult(query, SQL_FieldNameToNum(query, "pass"), playerData[id][PASSWORD], charsmax(playerData[][PASSWORD]));

		if (playerData[id][PASSWORD][0]) {
			new password[34], hash[34], info[32];

			formatex(info, charsmax(info), "_%s", setinfo);

			get_user_info(id, info, password, charsmax(password));
			
			hash_string(password, Hash_Md5, hash, charsmax(hash));

			if (equal(playerData[id][PASSWORD], hash)) {
				playerData[id][STATUS] = LOGGED;

				set_bit(id, autoLogin);

				ExecuteForward(loginForward, forwardResult, id);
				
				client_cmd(id, "seta ^"setu _%s^" %s", setinfo, password);

			} else {
				playerData[id][STATUS] = NOT_LOGGED;
			}
		}
	}

	set_bit(id, dataLoaded);
}

public account_query(id, type)
{
	if (!is_user_connected(id)) return;

	new queryData[192], password[34], hash[34];

	mysql_escape_string(playerData[id][PASSWORD], password, charsmax(password));
	
	hash_string(password, Hash_Md5, hash, charsmax(hash));

	switch (type) {
		case INSERT: formatex(queryData, charsmax(queryData), "INSERT INTO `csgo_accounts` (name, authid, pass) VALUES (^"%s^", ^"%s^", ^"%s^")", playerData[id][SAFE_NAME], playerData[id][AUTH_ID], hash);
		case UPDATE: {
			switch (saveType) {
				case SAVE_NAME: formatex(queryData, charsmax(queryData), "UPDATE `csgo_accounts` SET pass = '%s', authid = ^"%s^" WHERE name = ^"%s^"", hash, playerData[id][AUTH_ID], playerData[id][SAFE_NAME]);
				case SAVE_AUTH_ID: formatex(queryData, charsmax(queryData), "UPDATE `csgo_accounts` SET pass = '%s', name = ^"%s^" WHERE authid = ^"%s^"", hash, playerData[id][SAFE_NAME], playerData[id][AUTH_ID]);
			}
		}
		case DELETE: {
			switch (saveType) {
				case SAVE_NAME: formatex(queryData, charsmax(queryData), "DELETE FROM `csgo_accounts` WHERE name = ^"%s^"", playerData[id][SAFE_NAME]);
				case SAVE_AUTH_ID: formatex(queryData, charsmax(queryData), "DELETE FROM `csgo_accounts` WHERE authid = ^"%s^"", playerData[id][AUTH_ID]);
			}
		}
	}

	SQL_ThreadQuery(sql, "ignore_handle", queryData);
}

public ignore_handle(failState, Handle:query, error[], errorNum, data[], dataSize)
{
	if (failState) {
		if (failState == TQUERY_CONNECT_FAILED) log_to_file("csgo-error.log", "[CS:GO Accounts] Could not connect to SQL database. [%d] %s", errorNum, error);
		else if (failState == TQUERY_QUERY_FAILED) log_to_file("csgo-error.log", "[CS:GO Accounts] Query failed. [%d] %s", errorNum, error);
	}

	return PLUGIN_CONTINUE;
}

public _csgo_check_account(id)
{
	if (!accountsEnabled) {
		return true;
	}

	if (sql == Empty_Handle) {
		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_DATABASE_ERROR");

		return false;
	}

	if (playerData[id][STATUS] < LOGGED) {
		client_print(id, print_chat, "%s %L", CHAT_PREFIX, id, "CSGO_ACCOUNTS_LOGIN_FIRST");

		account_menu(id);

		return false;
	}

	return true;
}
