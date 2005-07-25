<?
	require("db.php");
?><!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
<head>
<title>pool.ntp.org server statistics</title>
<link rel="icon" href="http://www.ntp.org/favicon.ico" type="image/x-icon" />
</head>
<body style="background-color:white">
<hr/>
<h1><a href="/">pool.ntp.org</a> server statistics</h1>
<hr/>
<p><?
   if (!ereg(
      "^\s*([0-9]*)\.([0-9]*)\.([0-9]*)\.([0-9]*)\s*$", $server_ip, $chkip))
   {
      print("Error: '$server_ip' is no IP address\n");
   }
   else
   {
      $quit = 0;
      for ($loop = 1; $loop < 5; $loop++)
      {
        if ($chkip[$loop] > 255) { $quit = 1; }
      }
      if ($quit)
      {
        print("Error: '$server_ip' is no IP address\n");
      }
      else
      {
        $server_ip = "$chkip[1].$chkip[2].$chkip[3].$chkip[4]";
	$result = do_query("SELECT id, hostname FROM servers WHERE ip='".addslashes($server_ip)."'");
	if (pg_num_rows($result) > 0)
	{
		$arr = pg_fetch_array($result, 0, PGSQL_ASSOC);
		$server_id = $arr["id"];

		$url = "show_server_stats_do_graph.php?server_ip=".$server_ip;
		?><p>Scores for <? print $arr["hostname"]; ?> (<? print $server_ip; ?>), last 31 days:</p><?
		?><IMG SRC="<? print $url; ?>"><?
	}
	else
	{
		?>No server with that (<? print $server_ip; ?>) IP address.<?
	}
      }
   }
?><p>
Servers with a score of 5 or below are excluded from the DNS rotation.
<hr/>
<div style="font-size:x-small">
<div style="text-align:right">
<a href="http://www.vanheusden.com/" target="_new">Folkert van Heusden</a>
</div>
<pre>
$Log: show_server_stats_do.php,v $
Revision 1.6  2004/09/23 12:08:43  avbidder
 * French translation: Thanks, Vincent
 * Newsletter
 * Various small correction; thanks to various people

Revision 1.5  2004/06/21 08:35:42  avbidder
check IP addresses in PHP instead of PostgreSQL

Revision 1.4  2004/06/18 07:33:07  avbidder
 * Big load of thanks to Folkert
 * New scores version
 * announce scores publicly

Revision 1.3  2004/06/12 12:13:56  avbidder
 * html completely redone
 * static y-range in plot
 * of course, thanks a lot Folkert for doing the plot!

</pre>
</div>
</body>
</html>
