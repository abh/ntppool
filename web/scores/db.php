<?
function do_query($query)
{
	$conn = pg_pconnect("dbname=horas");

	$result = pg_query($query);

	return $result;
}
?>
