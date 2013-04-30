	my ($pt_id, $ot_id) = (1,2);
	print "PT_ID:$pt_id OT_ID:$ot_id\n";

	open (FILE, ">>", "id_map.txt");
	print FILE `date`;
	print FILE "$pt_id:$ot_id\n";
	close FILE;

