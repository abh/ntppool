<?
	$x_size_real = 778;
	$y_size_real = 270;
	$vertical_lines = 12;

	require("db.php");

	# find server in database
	$result = do_query("SELECT id FROM servers WHERE ip='".addslashes($server_ip)."'");
	if (pg_num_rows($result) > 0)
	{
		$arr = pg_fetch_array($result, 0, PGSQL_ASSOC);
		$server_id = $arr["id"];

		# init some variables used when querying the database
		# 30 days: includes also 23 hours and 59 minutes etc.!
		$selection = "server='".$server_id."' AND ts >= now()-interval '30 days'";

		# find min/max
                # ([vbi] static y range: so you see at a glance if a server
                # is good or bad)
		$min = -100;
		$max = 20;

		# initialize graph
		$horizontal_offset = 34;
		$vertical_offset = 12;
		$x_size = $x_size_real - ($horizontal_offset + 10);
		$y_size = $y_size_real - ($vertical_offset + 20);
		header("Content-type: image/png");
		$im = @imagecreate($x_size_real, $y_size_real) or die("Cannot Initialize new GD image stream");
		# init colors
		$col_white  = ImageColorAllocate($im, 255, 255, 255);
		$col_red    = ImageColorAllocate($im, 255, 0, 0);
		$col_redish = ImageColorAllocate($im, 255, 192, 192);
		$col_yellow = ImageColorAllocate($im, 255, 255, 0);
		$col_green  = ImageColorAllocate($im, 0, 255, 0);
		$col_blue   = ImageColorAllocate($im, 0, 0, 255);
		$col_gray   = ImageColorAllocate($im, 127, 127, 127);
		$col_black  = ImageColorAllocate($im, 0, 0, 0);
		# the red line
		$dummy_y = 1.5 * ($y_size / $vertical_lines);
		imageline($im, $horizontal_offset, $vertical_offset + $dummy_y, $horizontal_offset + $x_size, $vertical_offset + $dummy_y, $col_redish);
		# draw lines for each day
		for($loop=0; $loop<32; $loop++)
		{
			$x = $loop * ($x_size / 31);
			imageline($im, $x + $horizontal_offset, $vertical_offset, $x + $horizontal_offset, $y_size + $vertical_offset, $col_gray);
			imagestring($im, 0, $x + $horizontal_offset - 2, $y_size + $vertical_offset + 2, floor(31 - $loop), $col_black);
		}
		# split vertically
		for($loop=0; $loop<($vertical_lines + 1); $loop++)
		{
			$y = $loop * ($y_size / $vertical_lines);
			imageline($im, $horizontal_offset, $y + $vertical_offset, $x + $horizontal_offset, $y + $vertical_offset, $col_gray);
			imagestring($im, 0, 4, $y - 4 + $vertical_offset, substr(($vertical_lines - $loop) * (($max - $min) / $vertical_lines) + $min, 0, 5), $col_black);
		}
		# box around graph
		imageline($im, 0, 0, $x_size_real - 1, 0, $col_black);
		imageline($im, 0, $y_size_real - 1, $x_size_real - 1, $y_size_real - 1, $col_black);
		imageline($im, 0, 0, 0, $y_size_real - 1, $col_black);
		imageline($im, $x_size_real - 1, 0, $x_size_real - 1, $y_size_real - 1, $col_black);
		# arrow
		$dummy_y = $y_size + $vertical_offset;
		imageline($im, $horizontal_offset, $dummy_y, $horizontal_offset + 20, $dummy_y, $col_green);
		imageline($im, $horizontal_offset + 15, $dummy_y - 5, $horizontal_offset + 20, $dummy_y, $col_green);
		imageline($im, $horizontal_offset + 15, $dummy_y + 5, $horizontal_offset + 20, $dummy_y, $col_green);

		# draw graph
		$query = "SELECT EXTRACT(DAY FROM (now() - ts)) AS days, EXTRACT(HOUR FROM (now() - ts)) as hour, EXTRACT(MINUTE FROM (now() - ts)) as minute, EXTRACT(MILLISECONDS FROM (now() - ts)) as milliseconds, score, step FROM log_scores WHERE ".$selection." ORDER BY ts";
# echo $query;
		$result = do_query($query);
		$n_records = pg_num_rows($result);
		for($loop=0; $loop<$n_records; $loop++)
		{
			$arr = pg_fetch_array($result, $loop, PGSQL_ASSOC);

			$step = $arr["step"];
			if ($step == -5)
				$line_col = $col_red;
			else if ($step == -2)
				$line_col = $col_yellow;
			else if ($step == 1)
				$line_col = $col_green;
			else if ($step == 0.5)
				$line_col = $col_blue;
			else
				$line_col = $col_gray;

			$ts = ($arr["days"] * 24.0) + $arr["hour"] + ($arr["minute"] / 60.0) + ($arr["milliseconds"] / 60000.0);
			$x = (768 - $ts); # + $horizontal_offset;
			$y = ($y_size - ($arr["score"] - $min) * ($y_size / ($max - $min))) + $vertical_offset;

			if ($loop == 0)
			{
				$prev_x = $x;
				$prev_y = $y;
			}

			imageline($im, $prev_x, $prev_y, $x, $y, $line_col);
			$prev_x = $x;
			$prev_y = $y;
		}

		# send graph to client
		imagepng($im);
		imagedestroy($im);
	}
	else
	{
		?>IP address not found.<?
	}
?>
