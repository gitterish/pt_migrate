use XML::Simple;
use Data::Dumper;
use JSON;
use Getopt::Long;

my $ACCESS_TOKEN="aeb66e2c-3b59-4a53-94e6-594827405ab4";
my $WORKFLOW_STEP_NEW = 7;
my $WORKFLOW_STEP_COMPLETED = 11;

my $file_name, $do_post;
GetOptions ('storyfile:s'=>\$story_file_name,
            'mapfile:s'=>\$map_file_name,
            'post'=>\$do_post,
            'project:i'=>\$OT_PROJECT
						);

if (!defined $story_file_name || !defined $map_file_name || !defined $OT_PROJECT)
{
	print "Usage: $0 --storyfile=<filename> --mapfile=<filename> --post --project=<OT project id>\n";
	exit;
}

my $parser = XML::Simple->new ();
my $doc = $parser->XMLin ($file_name, ForceArray=>1);
#print Dumper($doc);
my @stories = @{$doc->{story}};
foreach $story (@stories)
{
	next if ($story->{current_state}->[0] eq "accepted");

	my ($pt_tasks, $ot_tasks) = process_story ($story);

	for ($i=0; $i < scalar (@$ot_tasks); $i++)
	{
		print "++++++++\n";
		#print "OT_INPUT:".Dumper ($ot_input)."\n";
		my $ot_input_json = encode_json ($ot_task->[$i]);
		print "$ot_input_json\n";
		if ($do_post)
		{
			my $ot_output_json = post_ot ($ot_input_json);
			if (defined $ot_output_json)
			{
				print "OUTPUT of POST: $ot_output_json\n";
				$ot_output = decode_json ($ot_output_json);
				print "OT ID: $ot_output->{data}->{id}\n";
				write_id_map_to_file ($pt_tasks->[$i]->{id}, $ot_output->{data}->{id});
			}
		}
}

sub process_story
{
	my $pt_story = shift;
	my $ot_tasks = [];
	my $pt_tasks = [];

#print Dumper($pt_story);
	#Tasks
	foreach $task (@{$pt_story->{tasks}->[0]->{task}})
	{
		push (@$pt_tasks, $task);

		my $ot_input = {};
		$ot_input->{item} = {};
		my $ot_item = $ot_input->{item};

		my $pt_desc = $task->{description}->[0];
		if (!ref $pt_desc)
		{
			$pt_desc =~ s!\n!<BR/>!g;
		}
		else
		{
			$pt_desc = "";
		}


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
		$ot_item->{description} = $pt_desc;

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
		if ($task->{complete}->[0]->{content} eq "true")
		{
			$ot_item->{workflow_step}->{id} = $WORKFLOW_STEP_COMPLETED; #completed
		}
		else
		{
			$ot_item->{workflow_step}->{id} = $WORKFLOW_STEP_NEW; #new
		}

#StartDate
		$ot_item->{start_date} = format_date($task->{created_at}->[0]->{content});

#CompletionDate
		if ($task->{complete}->[0]->{content} eq "true")
		{
			$ot_item->{completion_date} = format_date($task->{completion_date}->[0]->{content});
		}

#CustomFields:Type
		$type_map ={
			feature=>'FEATURE',
			bug=>'BUG',
			release=>'FEATURE',
			chore=>'FEATURE'
		};
		$ot_item->{custom_fields}->{custom_164} = $type_map->{$pt_story->{story_type}->[0]};

		push (@$ot_tasks, $ot_input);
	}

	return ($pt_tasks, $ot_tasks);
}

