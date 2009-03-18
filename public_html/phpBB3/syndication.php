<?php
/*
*
* @package phpBB3
* @version $Id: syndication.php,v 1.0 2006/11/27 22:29:16 angelside Exp $
* @copyright (c) Canver Software
* @license http://opensource.org/licenses/gpl-license.php GNU Public License
*
*/

/**
*/
define('IN_PHPBB', true);
$phpbb_root_path = './';
$phpEx = substr(strrchr(__FILE__, '.'), 1);
include($phpbb_root_path . 'common.' . $phpEx);

// Start session management
$user->session_begin();
$auth->acl($user->data);
$user->setup();

// Begin configuration
$CFG['exclude_forums'] 	= '';
$CFG['max_topics'] 		= 50;
// End configuration

// requests
$fid    = request_var('fid', '') || request_var('f', '');
$count 	= request_var('count', 15);
$chars 	= request_var('chars', 200);
$type 	= request_var('type', '');
$topics_only = request_var('t', '');

// If not set, set the output count to max_topics
$count = ( $count == 0 ) ? $CFG['max_topics'] : $count;

// maximum text char limit
if($chars<0 || $chars>500) $chars=500; //Maximum

// generate url
$board_url = generate_board_url();
$index_url = $board_url . '/index.' . $phpEx;
$viewtopic_url = $board_url . '/viewtopic.' . $phpEx;


// below three function barroved on "Full Syndication Suite 0.9.4a"

/**
* parse a message
*/
function parse_message($row, $bbcode_options, $bbcode_uid, $bbcode_bitfield)
{
	global $board_url;

	$row = html_entity_decode(generate_text_for_display($row, $bbcode_uid, $bbcode_bitfield, $bbcode_options));

	// smilies contain relative URL, we need it to be absolute
	return str_replace('<img src="./', '<img src="' . $board_url . '/', $row);
}

/**
* encode message for usage with RSS
*/
function rss_prepare_message(&$message)
{
	// embed message into CDATA tags in case it contains HTML tags or entities
	if (preg_match('/<[^>]+>|&#?[\w]+;/', $message))
	{
		// replace any ]]>
		$message = str_replace(']]>', ']]&gt;', $message);
		$message = '<![CDATA[' . $message . ']]>';
	}
}

/**
* create a date according to RFC 3339 or 822
*/
function format_date($timestamp)
{
	global $type;
	if ($type == 'atom')
	{
		// RFC 3339 for ATOM
		return date('Y-m-d\TH:i:s\Z', $timestamp);
	}
	else
	{
		// RFC 822 for RSS2
		return date('D, d M Y H:i:s O', $timestamp);
	}
}

$sql_where = '';

// only topic first post
if ($topics_only == 1) 
{
	$sql_where = 'AND p.post_id = t.topic_first_post_id';
	$sql_from = 'FROM ' . POSTS_TABLE . ' as p, ' . FORUMS_TABLE . ' as f, ' . USERS_TABLE . ' as u, ' . TOPICS_TABLE . ' as t';
}
else
{
	$sql_from = 'FROM ' . POSTS_TABLE . ' as p, ' . FORUMS_TABLE . ' as f, ' . USERS_TABLE . ' as u';
}

// Exclude forums
if ($CFG['exclude_forums'])
{
	$exclude_forums = explode(',', $CFG['exclude_forums']);
	foreach ($exclude_forums as $i => $id)
	{
		if ($id > 0)
		{
			$sql_where .= ' AND p.forum_id != ' . trim($id);
		}
	}
}

if ($fid != '')
{
	$select_forums = explode(',', $fid);
	$sql_where .= ( sizeof($select_forums)>0 ) ? ' AND f.forum_id IN (' . $fid . ')' : '';
}

// SQL posts table
$sql = 'SELECT p.poster_id, p.post_subject, p.post_text, p.bbcode_uid, p.bbcode_bitfield, p.topic_id, p.forum_id, p.post_time, f.forum_name, f.forum_desc_options, u.username
		' . $sql_from . '
		WHERE (u.user_id = p.poster_id)
		AND p.post_approved = 1
		AND (f.forum_id = p.forum_id)
		' . $sql_where . '
		ORDER BY post_time DESC';
$result = $db->sql_query_limit($sql, $count);

while( ($row = $db->sql_fetchrow($result)) )
{

	if (!$auth->acl_get('f_list', $row['forum_id']))
	{
		// if the user does not have permissions to list this forum, skip everything until next branch
		continue;
	}

	($type != 'atom') ? rss_prepare_message($row['post_text']) : '';

	$template->assign_block_vars('item', array(
		'AUTHOR'		=> $row['username'],
		'TIME'			=> format_date($row['post_time']),
//		'LINK'			=> append_sid("$board_url/viewtopic.$phpEx", 'f=' . $row['forum_id'] . '&amp;t=' . $row['topic_id']),
//		'IDENTIFIER'	=> append_sid("$board_url/viewtopic.$phpEx", 'f=' . $row['forum_id'] . '&amp;t=' . $row['topic_id']),
		'LINK'			=> append_sid("$board_url/viewtopic.$phpEx", 'f=' . $row['forum_id'] . '&amp;t=' . $row['topic_id']),
		'IDENTIFIER'	=> "$board_url/viewtopic.$phpEx", 'f=' . $row['forum_id'] . '&amp;t=' . $row['topic_id'],
		'TITLE'			=> $row['post_subject'],
		'TEXT'			=> parse_message($row['post_text'], $row['forum_desc_options'], $row['bbcode_uid'], $row['bbcode_bitfield']),		
		)
	);	
}

if ($type == 'atom')
{
	$template->assign_var('FEED_LINK', $board_url);
	$content_type = 'application/atom+xml';
	$tpl = 'atom';
}
else
{
	$content_type = 'application/rss+xml';
	$tpl = 'rss2';
}

$template->set_filenames(array(
	'body' => 'syndication_' . $tpl . '.xml')
);

// get time, use current time
$last_build_date = mktime();

$template->assign_vars(array(
	'HEADER'		=> '<?xml version="1.0" encoding="UTF-8"?>' . "\n", // workaround for remove_php_tags() removing this line from the template
	'TITLE'			=> strip_tags($config['sitename']),
	'DESCRIPTION'	=> strip_tags($config['site_desc']),
	'LINK'			=> $board_url,
 	'LAST_BUILD'	=> format_date($last_build_date)
	)
);

// gzip compression
if ($config['gzip_compress'])
{
	if (@extension_loaded('zlib') && !headers_sent())
	{
		ob_start('ob_gzhandler');
	}
}

// start output
header ('Content-Type: ' . $content_type . '; charset=UTF-8');
$template->display('body');
exit;

?>
