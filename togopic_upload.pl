#!/usr/bin/env perl

=head

This script uploads images of Togo Picture Gallery to Wikimedia Commons.
Input file is "TogoPics.csv", which is maintained by the DBCLS Togo Picture Gallery team.

http://togotv.dbcls.jp/ja/pics.html

Yasunori Yamamoto @ Database Center for Life Science

Acknowledgements:
    This script uses parts of the upload.pl rev. 1.3.2 developed by Nicholas:~ Wikipedia: [[en:User:Nichalp]],
    which is published under the GPLv3 licence.

=cut

use strict;
use warnings;
use Fatal qw/open/;
use utf8; 
use LWP::UserAgent;
use LWP::Protocol::https;
use Encode;
use Text::CSV_XS;
use Term::ReadKey;
use HTTP::Request::Common;
use JSON::XS;
use FindBin qw($Bin);

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my $image_dir = "$Bin/image_files";
my $csv = Text::CSV_XS->new({ binary => 1 });
my $file = 'TogoPics.csv';

# $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;

my $browser;
my $edit_token;
my ($username, $password);

my $ua = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:22.0) Gecko/20100101 Firefox/22.0";
my $api_url = "https://commons.wikimedia.org/w/api.php";
my $author = "DataBase Center for Life Science (DBCLS)";
my $togopic_root = "http://togotv.dbcls.jp/ja/";
my $togopicpng_root = "http://togotv.dbcls.jp/pic/";
my $licence = "{{cc-by-4.0}}";

&main;

sub downloadImage {
    my $lwp = LWP::UserAgent->new( agent => $ua );
    my $res = $lwp->get( $togopicpng_root. $_[0], ':content_file' => $image_dir. "/". $_[0] );

    if ( $res->is_success ) {
	print ">", $image_dir."/".$_[0], "\n";
    } else {
	print "Error. $!: ${togopicpng_root}$_[0] -> ${image_dir}/$_[0]\n";
	return 1;
    }
    return 0;
}

sub getAccountInfo {
    print "Enter your username: ";
    $username = <STDIN>;
    print "Enter your password: ";
    ReadMode('noecho');
    $password = ReadLine(0);
    ReadMode('normal');
    chomp ($username, $password);
    print "\n";
}

sub initBrowser {
    $browser = LWP::UserAgent->new( agent => $ua );
    $browser->default_header( 'Accept-Language' => 'en-US' );
    $browser->default_header( 'Accept-Charset' => 'iso-8859-1,*,utf-8' );
    $browser->default_header( 'Accept' => '*/*' );
    $browser->cookie_jar( {} );
}

sub loginAndGetToken {
    my $token = "";
    my $response = $browser->post(
	$api_url,
	Content_Type => "application/x-www-form-urlencoded",
	Content_Encoding => "utf-8",
	Content => [
	    "action"     => "login",
	    "lgname"     => $username,
	    "lgpassword" => $password,
	    "format"     => "json",
	]);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	$token = $res_ref->{"login"}->{"token"};
    }else{
	die "Post error: $!\n";
    }

    $response = $browser->post(
	$api_url,
	Content_Type => "application/x-www-form-urlencoded",
	Content_Encoding => "utf-8",
	Content=> [
	    "action"     => "login",
	    "lgname"     => $username,
	    "lgpassword" => $password,
	    "lgtoken"    => $token,
	    "format"     => "json",
	]);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	if($res_ref->{"login"}->{"result"} eq "Success"){
	    print "lguserid:", $res_ref->{"login"}->{"lguserid"}, "\n";
	    print "lgusername:", $res_ref->{"login"}->{"lgusername"}, "\n";
	}else{
	    open(my $debug, ">", "debug.txt");
	    print $debug $response->as_string;
	    close($debug);
	    die "Failed to login. Please check the file 'debug.txt'.\n";
	}
    } else {
	die "Post error: $!\n";
    }

    my $url = URI->new( $api_url );
    $url->query_form(
	"action" => "query",
	"meta"   => "tokens",
	"format" => "json",
	);
    $response = $browser->get($url);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	$edit_token = $res_ref->{"query"}->{"tokens"}->{"csrftoken"};
    }else{
	die "Get error: $!\n";
    }
}

sub uploadFile {

    my $p = shift;

    open (my $log, ">>", "log.txt");

    my $full_description = "\n{{". $p->{"description"}. "}}";

# Categories: Combining all categories as one master category
    my $mastercategory="[[Category:". $p->{"category_1"}. "]]";
    if ($p->{"category_2"} ne ""){
	$mastercategory.="\n[[Category:". $p->{"category_2"}. "]]" ;
    }
    if ($p->{"category_3"} ne ""){
	$mastercategory.="\n[[Category:". $p->{"category_3"}. "]]" ;
    }
    if ($p->{"category_4"} ne ""){
	$mastercategory.="\n[[Category:". $p->{"category_4"}. "]]" ;
    }
    if ($p->{"category_5"} ne ""){
	$mastercategory.="\n[[Category:". $p->{"category_5"}. "]]" ;
    }
    $mastercategory .= "\n\n";

#Other versions
    my $other_versions = "";
    if (($p->{"other_version1"} ne "") || ($p->{"other_version2"} ne "")){
	if ($p->{"other_version1"} ne ""){
	    $p->{"other_version1"} = "\n* [[:Image:". $p->{"other_version1"}. "|". $p->{"other_version1"}. "]]";
	}
	if ($p->{"other_version2"} ne ""){
	    $p->{"other_version2"} = "\n* [[:Image:". $p->{"other_version1"}. "|". $p->{"other_version1"}. "]]";
	}
	$other_versions = $p->{"other_version1"}. $p->{"other_version2"};
    }

# Information template
    my @templates = (
	"Information\n",
	"Description\t= $full_description\n",
	"Source\t= ". $p->{"source"}. "\n",
	"Author\t= $author\n",
	"Date\t\t= ". $p->{"date"}. "\n",
	"Permission\t= \n",
	"Other versions= $other_versions\n",
	);
    my $information = "\n== Summary ==\n\n";
    $information .= "{{". join("| ", @templates). "}}\n";
    print ">", $information, "\n";

# Begin optional template integration
    my $metadata = $information;
    if (defined $p->{"other_information"}) {
	$metadata .= "\n". $p->{"other_information"}. "\n";
    };

# Integrating remaining templates into one 
    $metadata .="\n== [[Commons:Copyright tags|Licensing]] ==\n$licence\n\n\n$mastercategory\n\n";

    my $description = $p->{"description"};
    my $current_name = $p->{"current_name"};
    my $original_png = $p->{"original_png"};

    print "Uploading $current_name to the Wikimedia Commons. \nDescription: ";
    print $description, "\n";

    my $url = URI->new( $api_url );
    my $response = $browser->post(
	$url,
	Content_Type     => "multipart/form-data",
	Content_Encoding => "utf-8",
	Content => [
	    "action"   => "upload",
	    "filename" => $original_png,
	    "file"     => ["$current_name"],
	    #"url"     => $source,
	    "token"    => $edit_token,
	    "text"     => encode_utf8($metadata),
	    "format"   => "json",
	]);

    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
        print "Upload:", $res_ref->{"upload"}->{"result"}, "\n";
        if($res_ref->{"upload"}->{"result"} eq "Success"){
            print "Uploaded successfully.\n";
            print $log encode_utf8("Image:$current_name|$description\n");
            print $response->content, "\n";
            print $log $response->content, "\n";
        } else {
            print "Upload failed! Output was:\n";
            print $response->content, "\n";
        }
    }else{
        die "Post error: $!\n";
    }

    close($log);
}

sub main {

    &getAccountInfo;
    &initBrowser;
    &loginAndGetToken;

    open(my $data, '<:utf8', $file);
    <$data>;
    while (<$data>) {
	chomp;
	if ($csv->parse($_)) {
	    my ($picture_id, $togopic_id, $taxicon_id, $update, $doi, $date,
		$title_jp, $title_en, $scientific_name, $tax_id, $tag, $original_png,
		$original_svg, $original_ai, $DatabaseArchiveURL) = $csv->fields();       

	    next unless $picture_id;
	    $doi //= "";
	    $date //= "";
	    $title_jp //= "";
	    $title_en //= "";
	    $scientific_name //= "";
	    $tax_id //= "";
	    $tag //= "";
	    $original_png //= "";
	    my $description = "{{en|$title_en}}{{ja|$title_jp}}";
	    next if downloadImage($original_png);
	    my $current_name = $image_dir. '/'. $original_png;
	    my $source = $togopic_root. $doi. ".html";

	    uploadFile(
		{
		    "date"         => $date,
		    "description"  => $description,
		    "current_name" => $current_name,
		    "source"       => $source,
		    "original_png" => $original_png,
		    "category_1"   => "Biology",
		    "category_2"   => "",
		    "category_3"   => "",
		    "category_4"   => "",
		    "category_5"   => "",
		    "other_information" => "",
		    "other_version1"    => "",
		    "other_version2"    => "",
		});

	} else {
	    warn "Parse error: $_\n";
	}

	sleep 3;

    }
}

__END__
