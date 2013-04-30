use XML::Simple;
use Data::Dumper;
use JSON;
use Getopt::Long;

my $ACCESS_TOKEN="aeb66e2c-3b59-4a53-94e6-594827405ab4";
my $WORKFLOW_STEP_NEW = 7;
my $WORKFLOW_STEP_COMPLETED = 11;

my $file_name, $do_post;
GetOptions ('file:s'=>\$file_name,
            'post'=>\$do_post,
            'project:i'=>\$OT_PROJECT
						);

if (!defined $file_name || !defined $OT_PROJECT)
{
	print "Usage: $0 --file=<filename> --post --project=<OT project id>\n";
	exit;
}

my $parser = XML::Simple->new ();
my $doc = $parser->XMLin ($file_name, ForceArray=>1);
#print Dumper($doc);
my @stories = @{$doc->{story}};
foreach $story (@stories)
{
	my ($ot_input, $ot_type) = process_story ($story);
	if ($ot_input->{item}->{workflow_step}->{id} == $WORKFLOW_STEP_COMPLETED)
	{
		print "$story->{id}->[0]->{content}|PT Complete\n";
		next;
	}
	print "++++++++\n";
	#print "OT_INPUT:".Dumper ($ot_input)."\n";
	#print "OT_TYPE:$ot_type\n";
	my $ot_input_json = encode_json ($ot_input);
	print "$story->{id}->[0]->{content}|PT Pending\n";
	print "$ot_input_json\n";
	if ($do_post)
	{
		my $ot_output_json = post_ot ($ot_input_json, $ot_type);
		if (defined $ot_output_json)
		{
			print "OUTPUT of POST: $ot_output_json\n";
			$ot_output = decode_json ($ot_output_json);
			print "OT ID: $ot_output->{data}->{id}\n";
			write_id_map_to_file ($story, $ot_output->{data}->{id});
		}
	}
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

sub post_ot
{
	my ($ot_input_json, $ot_type) = @_;
	my $ot_url = "https://convirture.ontimenow.com/api/v1/$ot_type?access_token=$ACCESS_TOKEN";
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

sub process_story
{
	my $pt_story = shift;
	my $ot_type = "features";

#print Dumper($pt_story);
	my $ot_input = {};
	$ot_input->{item} = {};
	my $ot_item = $ot_input->{item};

#Project
	my $pt_labels =  $pt_story->{labels}->[0];
	if ($pt_labels =~ /ee[,<]/)
	{
		$ot_item->{project}->{id} = 21;#Convirt-Enterprise
	}
	elsif ($pt_labels =~ /ec2,/ or $pt_labels =~ /ec2$/)
	{
		$ot_item->{project}->{id} = 20;#Convirt-Cloud
	}
	else
	{
#Default
		$ot_item->{project}->{id} = $OT_PROJECT;
	}

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

	#Severity
	$pt_labels =  $pt_story->{labels}->[0];
	if ($pt_labels =~ /s(\d)/)
	{
		$severity_hash = {
			0=>'Critical',
			1=>'High Impact',
			2=>'Medium Impact',
			3=>'Low Impact'
		};
		#$ot_item->{severity} = $1;
		$ot_item->{custom_fields}->{custom_171} = $severity_hash->{$1};
	}

	#Priority
	$pt_labels =  $pt_story->{labels}->[0];
	if ($pt_labels =~ /p(\d)/)
	{
		$priority_hash = {
			0=>"1",
			1=>"3",
			2=>"2",
			3=>"2"
		};
		$ot_item->{priority}->{id} = $priority_hash->{$1};
	}

#Status
	if ($pt_story->{current_state}->[0] eq "accepted")
	{
		$ot_item->{workflow_step}->{id} = $WORKFLOW_STEP_COMPLETED; #completed
	}
	else
	{
		$ot_item->{workflow_step}->{id} = $WORKFLOW_STEP_NEW; #new
	}

#StartDate
	$ot_item->{start_date} = format_date($pt_story->{created_at}->[0]->{content});

#CompletionDate
	if ($pt_story->{current_state}->[0] eq "accepted")
	{
		$ot_item->{completion_date} = format_date($pt_story->{accepted_at}->[0]->{content});
	}

#CustomFields:Type
	$type_map ={
		feature=>'FEATURE',
		bug=>'BUG',
		release=>'FEATURE',
		chore=>'FEATURE'
	};
	$ot_item->{custom_fields}->{custom_164} = $type_map->{$pt_story->{story_type}->[0]};

	return ($ot_input, $ot_type);
}
