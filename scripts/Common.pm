sub post_ot
{
	my $ot_input_json = shift;
	my $ot_url = "https://convirture.ontimenow.com/api/v1/feature?access_token=$ACCESS_TOKEN";
	print "URL for POST: $ot_url\n";
	print "JSON for POST: $ot_input_json\n";
	use LWP::UserAgent;
	use HTTP::Request::Common;

	my $userAgent = LWP::UserAgent->new(agent => 'perl post');
	my $response = $userAgent->request(POST $ot_url,
	Content_Type => 'application/json',
	Content => $ot_input_json);

	if (!$response->is_success)
	{
		print $response->error_as_HTML;
		return;
	}
	else
	{
		return $response->content;
	}
}


sub format_date
{
	my $date = shift;
	$date =~ s!/!-!g;
	$date =~ s! !T!;
	$date =~ s! ...$!Z!;
	return $date;
}

sub write_id_map_to_file
{
	my ($pt_story, $ot_id) = @_;
	print "PT_ID:$pt_story->{id}->[0]->{content} OT_ID:$ot_id\n";

	open (FILE, ">>", "id_map.txt");
	if (!$date_written)
	{
		print FILE `date`;
		$date_written = 1;
	}
	my $pt_id = "$pt_story->{id}->[0]->{content}";
	my $pt_task;
	foreach $task (@{$pt_story->{tasks}->[0]->{task}})
	{
		$pt_task .= "," if (defined $pt_task);
		$pt_task .= "$task->{id}->[0]->{content}";
	}
	print FILE "$pt_id|$pt_task|$ot_id\n";
	close FILE;
}

