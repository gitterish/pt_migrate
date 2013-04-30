#####################################################################################
# pt_migrate.pl: Script to migrate PivotalTracker tasks to OntimeNow
# Run perl pt_migrate.pl for options
#
#####################################################################################
use XML::Simple;
use Data::Dumper;
use JSON;
use Getopt::Long;
use LWP::UserAgent;
use HTTP::Request::Common;
use URI::Encode;

my $OPTIONS = {};
my $WORKFLOW_STEP_COMPLETED = 11;

sub debug
{
	print "@_" if (defined $OPTIONS->{debug});
}

sub load_cfg
{
	my $cfg_file = shift;

	return if (!defined $cfg_file);

	open FILE, "$cfg_file" or die "cannot open $cfg_file\n";
	while (<FILE>)
	{
		chomp;
		next if (/^#/);
		next if (/^$/);
		next if (/^\s+/);
		my ($key, $value) = split /=/;
		#print "key:$key : $value\n";
		$OPTIONS->{$key} = $value;
	}
	close FILE;

	return $OPTIONS;
}

sub check_options
{
	if (!defined $OPTIONS->{story_file_name})
	{
		return "Missing story file name";
	}
	if (!defined $OPTIONS->{OT_URL})
	{
		return "Missing OT URL";
	}
	if (!defined $OPTIONS->{OT_ACCESS_TOKEN})
	{
		return "Missing OT access token";
	}
	if (!defined $OPTIONS->{PT_SESSION})
	{
		return "Missing PT session";
	}

	return;
}

sub download_attachment
{
	my $pt_id = shift;
	my $url = shift;

	debug "Downloading Attachment URL: $url\n";
	my $userAgent = LWP::UserAgent->new(agent => 'perl get');
	$userAgent->requests_redirectable( [] );
	my $response = $userAgent->request(GET $url,
	Cookie => "t_session=$OPTIONS->{PT_SESSION}"
	);

	if (!$response->is_success or $response->code =~ /3../)
	{
		print "[PT_ID: $pt_id] Error downloading attachment: $url\n";
		return;
	}

	debug "Download successful: $url\n";
	return $response->content;
}

sub encode
{
	my $content = shift;
	my $enc_content;

	open (FILE, ">", \$enc_content) or die "Could not open string for writing\n";
	binmode FILE, ":utf8";
	print FILE $content;
	close FILE;

	return $enc_content;
}

sub process_attachments
{
	my $pt_story = shift;
	my $ot_id = shift;

	my $pt_id = $pt_story->{id}->[0]->{content};

	foreach $attachment (@{$pt_story->{attachments}->[0]->{attachment}})
	{
		my $filename = $attachment->{filename}->[0];
		my $content = download_attachment ($pt_id, $attachment->{url}->[0]);
		if (!defined $content)
		{
			print "[PT_ID: $pt_id] Error: Unable to download attachment [$filename]\n";
			next;
		}
		debug "Attachment size: " . length($content) . "\n";
		my $enc_content = encode ($content);

		if (defined $ot_id && $OPTIONS->{do_post})
		{
			$response = post_attachment ($pt_id, $ot_id, $attachment, $enc_content);
			if (!defined $response)
			{
				print "[PT_ID: $pt_id] Error: Unable to post attachment [$filename]\n";
				next;
			}
		}
	}
}

sub post_attachment
{
	my ($pt_id, $ot_id, $attachment, $content) = @_;

	my $desc = $attachment->{description}->[0];
	if (!ref $desc)
	{
		$desc =~ s!\n! !g;
	}
	else
	{
		undef $desc;
	}

	my $url = "$OPTIONS->{OT_URL}/api/v1/features/$ot_id/attachments?access_token=$OPTIONS->{OT_ACCESS_TOKEN}";
	$url .= "&file_name=$attachment->{filename}->[0]";
	$url .= "&description=Created:$attachment->{uploaded_at}->[0]->{content}";
	$url .= " $desc" if (defined $desc);

	my $encoder = URI::Encode->new ();
	$url = $encoder->encode ($url);

	debug "URL for POST: $url\n";

	my $userAgent = LWP::UserAgent->new(agent => 'perl get');
	my $response = $userAgent->request(POST $url,
	Content_Type => 'application/octet-stream',
	Content => $content);

	if (!$response->is_success)
	{
		print "[PT_ID: $pt_id] Error uploading attachment: [$response->error_as_HTML]";
		return;
	}
	debug $response->content;
}

sub write_id_map_to_file
{
	return if (!defined $OPTIONS->{map_file_name});

	my ($pt_story, $ot_id) = @_;
	debug "PT_ID:$pt_story->{id}->[0]->{content} OT_ID:$ot_id\n";

	open (FILE, ">>", "$OPTIONS->{map_file_name}");
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

sub post_ot
{
	my ($pt_id, $ot_input_json, $ot_type) = @_;

	my $ot_url = "$OPTIONS->{OT_URL}/api/v1/$ot_type?access_token=$OPTIONS->{OT_ACCESS_TOKEN}";
	debug "URL for POST: $ot_url\n";
	debug "JSON for POST: $ot_input_json\n";

	my $userAgent = LWP::UserAgent->new(agent => 'perl post');
	my $response = $userAgent->request(POST $ot_url,
	Content_Type => 'application/json',
	Content => $ot_input_json);

	if (!$response->is_success)
	{
		print "[PT_ID: $pt_id] Error uploading to OT: [" . $response->error_as_HTML . "]";
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

sub map_value
{
	my $map = shift;
	my $string = shift;
	my $value;

	debug "MAP_VALUE [$map] [$string]\n";

	return if (!defined $map);

	my $dec_map = decode_json ($map);
	foreach $key (keys %$dec_map)
	{
		if ($string =~ /\b$key\b/)
		{
			$value = $dec_map->{$key};
		}
	}
	if (!defined $value)
	{
		$value = $dec_map->{DEFAULT};
	}
	return $value;
}

sub convert_to_ot_task
{
	my $pt_story = shift;
	my $ot_type = "features";

#print Dumper($pt_story);
	my $ot_input = {};
	$ot_input->{item} = {};
	my $ot_item = $ot_input->{item};

	#Name
	$ot_item->{name} = "$pt_story->{name}->[0] ($pt_story->{id}->[0]->{content})";

	#Description
	$ot_item->{description} =
"<A HREF=\"$pt_story->{url}->[0]\">$pt_story->{url}->[0]</A>";
	if (defined $pt_story->{labels}->[0])
	{
		$ot_item->{description} .= " Labels:$pt_story->{labels}->[0]";
	}
	$ot_item->{description} .= "<BR/>" .
"Requested By:$pt_story->{requested_by}->[0]<BR/>" .
"Owned By:$pt_story->{owned_by}->[0]<BR/>";

	my $pt_desc = $pt_story->{description}->[0];
	if (!ref $pt_desc)
	{
		$pt_desc =~ s!\n!<BR/>!g;
		$ot_item->{description} .= "$pt_desc<BR/>"
	}
;

	#Tasks
	my $task_line;
	foreach $task (@{$pt_story->{tasks}->[0]->{task}})
	{
		my $pt_desc = $task->{description}->[0];
		if (!ref $pt_desc)
		{
			$pt_desc =~ s!\n!<BR/>!g;
		}
		else
		{
			$pt_desc = "";
		}
		$task_line .= "* $pt_desc ($task->{created_at}->[0]->{content})" . " - " . ($task->{complete}->[0]->{content} eq "true" ? "Completed" : "Pending") . "<BR/>";
	}
	if (defined $task_line)
	{
		$ot_item->{description} .= "<BR/>Tasks<BR/>===========<BR/>$task_line<BR/><BR/>";
	}

	#Story Type
	#my $pt_type =  $pt_story->{story_type}->[0];
	#$ot_type = "features";

	#Notes
	foreach $note (@{$pt_story->{notes}->[0]->{note}})
	{
		my $pt_time = $note->{noted_at}->[0]->{content};
		my $pt_text = $note->{text}->[0];
		if (!ref $pt_text)
		{
			$pt_text =~ s!\n!<BR/>!g;
		}
		else
		{
			$pt_text = "";
		}
		$ot_item->{notes} .= "$pt_time<BR/>$pt_text<BR/><BR/>";
	}

	my $value;
	$value = map_value ($OPTIONS->{PROJECT_MAP}, $pt_story->{labels}->[0]);
	$ot_item->{project}->{id} = $value if (defined $value);
	$value = map_value ($OPTIONS->{SEVERITY_MAP}, $pt_story->{labels}->[0]);
	$ot_item->{severity}->{id} = $value if (defined $value);
	$value = map_value ($OPTIONS->{PRIORITY_MAP}, $pt_story->{labels}->[0]);
	$ot_item->{priority}->{id} = $value if (defined $value);
	$value = map_value ($OPTIONS->{STATE_MAP}, $pt_story->{current_state}->[0]);
	$ot_item->{workflow_step}->{id} = $value if (defined $value);

	if (defined $OPTIONS->{TYPE_CUSTOM_FIELD})
	{
		$ot_item->{custom_fields}->{"$OPTIONS->{TYPE_CUSTOM_FIELD}"} = map_value ($OPTIONS->{TYPE_MAP}, $pt_story->{story_type}->[0]);
	}

#StartDate
	$ot_item->{start_date} = format_date($pt_story->{created_at}->[0]->{content});

#CompletionDate
	if ($pt_story->{current_state}->[0] eq "accepted")
	{
		$ot_item->{completion_date} = format_date($pt_story->{accepted_at}->[0]->{content});
	}

	return ($ot_input, $ot_type);
}

sub process_story
{
	my $story = shift;

	my $ot_id;
	my $pt_id = $story->{id}->[0]->{content};

	my ($ot_input, $ot_type) = convert_to_ot_task ($story);
	if ($OPTIONS->{SKIP_ACCEPTED} && $ot_input->{item}->{workflow_step}->{id} == $WORKFLOW_STEP_COMPLETED)
	{
		print "[PT_ID: $pt_id] Complete. Skipping...\n";
		return;
	}

	#print "OT_INPUT:".Dumper ($ot_input)."\n";
	#print "OT_TYPE:$ot_type\n";

	my $ot_input_json = encode_json ($ot_input);
	print "[PT_ID: $pt_id] Pending. Will Process...\n";
	debug "$ot_input_json\n";

	if ($OPTIONS->{do_post})
	{
		my $ot_output_json = post_ot ($pt_id, $ot_input_json, $ot_type);
		if (defined $ot_output_json)
		{
			debug "OUTPUT of POST: $ot_output_json\n";
			$ot_output = decode_json ($ot_output_json);
			$ot_id = $ot_output->{data}->{id};
			debug "OT ID: $ot_id\n";
			write_id_map_to_file ($story, $ot_id);
		}
	}

	process_attachments ($story, $ot_id);

	return $ot_id;
}

############ MAIN PROGRAM ###############
GetOptions ('storyfile:s'=>\$OPTIONS->{story_file_name},
            'post'=>\$OPTIONS->{do_post},
            'cfgfile:s'=>\$OPTIONS->{cfg_file_name},
            'mapfile:s'=>\$OPTIONS->{map_file_name},
						'verbose' => \$OPTIONS->{debug}
						);
load_cfg ($OPTIONS->{cfg_file_name});

my $error = check_options();
if (defined $error)
{
	print $error . "\n";
	print <<USAGE;
Usage: $0 --cfgfile=<cfg file> --storyfile=<story file> --mapfile=<map file> --post --verbose
Options
--cfgfile: The config file with options to control migration. Mandatory.
--storyfile: The file containing PT story XML. Mandatory.
--mapfile: The file that will store mapping of PT and OT Ids. Optional.
--post: If set, will carry out the upload of the migrated story to OT. IF not set, will only print the input JSON to upload the OT story; will not actually affect the OT system.
--verbose: Enables debug logging
USAGE
	exit;
}

my $parser = XML::Simple->new ();
my $doc = $parser->XMLin ($OPTIONS->{story_file_name}, ForceArray=>1);
#print Dumper($doc);
my @stories = @{$doc->{story}};
foreach $story (@stories)
{
	my $ot_id = process_story ($story);
	print "[PT_ID: $story->{id}->[0]->{content}] Done processing story. [OT_ID: $ot_id]\n";
}

