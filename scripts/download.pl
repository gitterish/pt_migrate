use XML::Simple;
use Data::Dumper;
use JSON;
use Getopt::Long;

my $file_name, $do_post;
GetOptions ('storyfile:s'=>\$story_file_name
						);

if (!defined $story_file_name)
{
	print "Usage: $0 --storyfile=<filename>\n";
	exit;
}

my $parser = XML::Simple->new ();
my $doc = $parser->XMLin ($story_file_name, ForceArray=>1);
#print Dumper($doc);
my @stories = @{$doc->{story}};
foreach $story (@stories)
{
	next if ($story->{current_state}->[0] eq "accepted");

	foreach $attachment (@{$story->{attachments}->[0]->{attachment}})
	{
		my $filename = $attachment->{filename}->[0];
		my $url = $attachment->{url}->[0];
		print "OT ID: $pt_story->{id}->[0]->{content} File: $filename URL: $url\n";

		`curl --cookie t_session=BAh7DToWc2tpcF9lcnJvcl9lc2NhcGVUOhRsYXN0X2xvZ2luX2RhdGVVOiBBY3RpdmVTdXBwb3J0OjpUaW1lV2l0aFpvbmVbCEl1OglUaW1lDUFMHMAAAJCwBjofQG1hcnNoYWxfd2l0aF91dGNfY29lcmNpb25UIh9QYWNpZmljIFRpbWUgKFVTICYgQ2FuYWRhKUl1OwgNMkwcwAAAkLAGOwlUOg9leHBpcmVzX2F0SXU7CA0iTRyAlmQGSQY7CUY6D3Nlc3Npb25faWQiJTg2OWUwNGFmMTQ5OTA5NWExZjIwMTVkNzYzMzU4NzQyIgpmbGFzaElDOidBY3Rpb25Db250cm9sbGVyOjpGbGFzaDo6Rmxhc2hIYXNoewY6CmVycm9yMAY6CkB1c2VkewY7DVQ6FXNpZ25pbl9wZXJzb25faWRpAyOkBToddmlld2VkX2Rhc2hib2FyZF9tZXNzYWdlVDoQX2NzcmZfdG9rZW4iMWZYN0NhN0pZaWt3V0QwL05oOGJURGkyVzdRUWQrYTh0WXNsRFNzRlBZOXM9--9ae6bba912de0206fdacbbc672721ccd16cab12f $url -o $filename`

	}
}
