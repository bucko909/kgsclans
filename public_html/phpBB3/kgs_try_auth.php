<?php

session_start();
define('IN_PHPBB', true);
$phpbb_root_path = (defined('PHPBB_ROOT_PATH')) ? PHPBB_ROOT_PATH : './';
$phpEx = substr(strrchr(__FILE__, '.'), 1);
require($phpbb_root_path . 'common.' . $phpEx);
require($phpbb_root_path . 'includes/functions_display.' . $phpEx);
require($phpbb_root_path . 'includes/functions_user.' . $phpEx);

// Start session management
$user->session_begin();

// Render a default page if we got a submission without an openid
// value.
if (empty($_POST['kgs_username'])) 
{
    exit(0);
}

$cocks = array();

$m=exec("/home/kgs/public_html/forum/kgs_logintest.sh ".escapeshellarg($_POST['kgs_username'])." ".escapeshellarg($_POST['kgs_password']), $cocks, $retval);
if ($retval) {
	// Failure
	trigger_error("Login failed; please try again.");
} else {
    // This means the authentication succeeded.
    $openid = "http://www.gokgs.com/openid/$_POST[kgs_username]";

    $sql = "SELECT *
            FROM " . USERS_TABLE . "
    WHERE user_openid = '$openid' ";
    if ( !($result = $db->sql_query($sql)) )
    {
        message_die(GENERAL_ERROR, 'Error in obtaining userdata', '', __LINE__, __FILE__, $sql);
    }
    if( $row = $db->sql_fetchrow($result) )
    {
        $user->session_create($row['user_id']);
    }
    else
    {
        $_SESSION['openid'] = $openid;
        if (empty($user->lang))
        {
            $user->setup();
        }
        $user->lang["REG_FROM_OPENID"] = "Create User from OpenID";
        page_header($user->lang["REG_FROM_OPENID"]);
        $template->assign_var("OPEN_ID", $openid);
        $usernameFromOpenID = $_POST['kgs_username'];
        $sql = "SELECT *
                FROM " . USERS_TABLE . "
        WHERE username = '$usernameFromOpenID' ";
        if ( !($result = $db->sql_query($sql)) )
        {
            message_die(GENERAL_ERROR, 'Error in obtaining userdata', '', __LINE__, __FILE__, $sql);
        }
        if( !($row = $db->sql_fetchrow($result)) )
        {
            $template->assign_var("USERNAME_FROM_OPENID", $usernameFromOpenID);
        }
        $template->assign_var("PASSWORD_FOR_KGS", $_POST['kgs_password']);

        $template->set_filenames(array("body" => "new_openid_user.html"));
        page_footer();
        exit;
    }
    header ("Location: index.php");
}
?>
