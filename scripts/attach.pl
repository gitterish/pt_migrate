use XML::Simple;
use Data::Dumper;
use JSON;
use Getopt::Long;
use URI::Encode;
use LWP::UserAgent;
use HTTP::Request::Common;

my $OPTIONS = {};
my $ID_MAP = {};

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

sub download_attachment
{
	my $url = shift;

	print "Downloading Attachment URL: $url\n";
	my $userAgent = LWP::UserAgent->new(agent => 'perl get');
	$userAgent->requests_redirectable( [] );
	my $response = $userAgent->request(GET $url,
	Cookie => "t_session=$OPTIONS->{PT_SESSION}"
	);

	if (!$response->is_success or $response->code =~ /3../)
	{
		print "Error downloading attachment: $url\n";
		return;
	}

	print "Download successful: $url\n";
	#print $response->content;
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

sub process_story
{
	my $pt_story = shift;

	my $pt_id = $pt_story->{id}->[0]->{content};
	my $ot_id = get_ot_id ($pt_id);
	if (!defined $ot_id)
	{
		print "Error: No OT ID mapping found for $pt_id\n";
		next;
	}

	print "OT ID $ot_id found for $pt_id\n";

	foreach $attachment (@{$pt_story->{attachments}->[0]->{attachment}})
	{
		my $filename = $attachment->{filename}->[0];
		my $content = download_attachment ($attachment->{url}->[0]);
		if (!defined $content)
		{
			print "Error: Unable to download attachment for $pt_id : $filename\n";
			next;
		}
		print "Attachment size: " . length($content) . "\n";
		my $enc_content = encode ($content);

		if ($OPTIONS->{do_post})
		{
			$response = post_attachment ($ot_id, $attachment, $enc_content);
			if (!defined $response)
			{
				print "Error: Unable to post attachment for $pt_id : $filename\n";
				next;
			}
		}
	}
}

sub post_attachment
{
	my ($ot_id, $attachment, $content) = @_;

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

	print "URL for POST: $url\n";

	my $userAgent = LWP::UserAgent->new(agent => 'perl get');
	my $response = $userAgent->request(POST $url,
	Content_Type => 'application/octet-stream',
	Content => $content);

	if (!$response->is_success)
	{
		print $response->error_as_HTML;
		return;
	}
	print $response->content;
}

sub get_ot_id
{
	my $pt_id = shift;

	return $ID_MAP->{$pt_id}->{OT_ID};
}

sub load_id_map
{
	#return if (defined $ID_MAP);

	open (FILE, "<", "$OPTIONS->{map_file_name}") or die "Unable to read id map\n";
	while (<FILE>)
	{
		chomp;
		my ($pt_id, $task_ids, $ot_id) = split /\|/;
		#print "Mapping: $pt_id: $ot_id\n";
		next if (!(defined $pt_id and defined $ot_id));
		$ID_MAP->{$pt_id}->{OT_ID} = $ot_id;
	}
	close FILE;
}

############### MAIN PROGRAM #################

GetOptions ('storyfile:s'=>\$OPTIONS->{story_file_name},
            'mapfile:s'=>\$OPTIONS->{map_file_name},
            'post'=>\$OPTIONS->{do_post},
            'cfg:s'=>\$OPTIONS->{cfg_file}
						);
load_cfg ($OPTIONS->{cfg_file});

if (!defined $OPTIONS->{story_file_name} || !defined $OPTIONS->{map_file_name})
{
	print "Usage: $0 --cfg=<cfg file> --storyfile=<filename> --mapfile=<filename> --post\n";
	exit;
}
if (!defined $OPTIONS->{OT_URL} || !defined $OPTIONS->{OT_ACCESS_TOKEN} or !defined $OPTIONS->{PT_SESSION})
{
	print "Missing OT_URL or OT_ACCESS_TOKEN in config\n";
	exit;
}

load_id_map ();

my $parser = XML::Simple->new ();
my $doc = $parser->XMLin ($OPTIONS->{story_file_name}, ForceArray=>1);
#print Dumper($doc);
my @stories = @{$doc->{story}};
foreach $story (@stories)
{
	next if ($story->{current_state}->[0] eq "accepted");
	process_story ($story);
}

