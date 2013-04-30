use LWP::UserAgent;
use HTTP::Request::Common;

local $/ = undef;
open FILE, "vdc_users_new.png";
$content = <FILE>;
close FILE;

my $enc_content;
open (FILE, ">", \$enc_content) or die "Could not open string for writing\n";
binmode FILE, ":utf8";
print FILE $content;
close FILE;

#print "ENC:$enc_content\n";

my $userAgent = LWP::UserAgent->new(agent => 'perl post');
my $response = $userAgent->request(POST "https://convirture.ontimenow.com/api/v1/features/1544/attachments?access_token=aeb66e2c-3b59-4a53-94e6-594827405ab4&file_name=vdc_users_new.png&description=TestFile",
Content_Type => 'application/octet-stream',
Content => $enc_content);

if (!$response->is_success)
{
	print $response->error_as_HTML;
}
else
{
	print $response->content;
}
