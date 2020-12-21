#!/usr/bin/env perl

=head

This script edits URL of Togo Picture Gallery to Wikimedia Commons.
Input file is "togopic_doi_convert.csv", which is maintained by the DBCLS Togo Picture Gallery team.

http://togotv.dbcls.jp/pics.html

Yasunori Yamamoto @ Database Center for Life Science

Acknowledgements:
    This script uses parts of the upload.pl rev. 1.3.2 developed by Nicholas:~ Wikipedia: [[en:User:Nichalp]],
    which is published under the GPLv3 licence.

このファイルはUTF-8エンコードされた文字を含みます。
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
use Text::Trim;
use File::stat;
use Fcntl qw/:mode/;
use constant EP => "https://query.wikidata.org/sparql";

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my $image_dir = "$Bin/image_files";
my $csv = Text::CSV_XS->new({ binary => 1 });
my $file = 'togopic_doi_convert.csv';

my $browser;
my $ua = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:22.0) Gecko/20100101 Firefox/22.0";
my $api_url = "https://commons.wikimedia.org/w/api.php";
my $author = "DataBase Center for Life Science (DBCLS)";
my $togopic_root = "http://togotv.dbcls.jp/ja/";
my $togopic_ftphost = 'ftp.biosciencedbc.jp';
my $togopic_ftppath = '/archive/togo-pic/image';
my $licence = "{{cc-by-4.0}}";
my %j2e;

&main;

sub getAccountInfo {
    my ($username, $password);
    print "Enter your username: ";
    $username = <STDIN>;
    print "Enter your password: ";
    ReadMode('noecho');
    $password = ReadLine(0);
    ReadMode('normal');
    chomp ($username, $password);
    print "\n";
    return [$username, $password];
}

sub initBrowser {
    $browser = LWP::UserAgent->new( agent => $ua );
    $browser->default_header( 'Accept-Language' => 'en-US' );
    $browser->default_header( 'Accept-Charset' => 'iso-8859-1,*,utf-8' );
    $browser->default_header( 'Accept' => '*/*' );
    $browser->cookie_jar( {} );
}

sub loginAndGetToken {
    my $userinfo = &getAccountInfo;
    my $token = "";
    my $response = $browser->post(
	$api_url,
	Content_Type => "application/x-www-form-urlencoded",
	Content_Encoding => "utf-8",
	Content => [
	    "action"     => "login",
	    "lgname"     => $userinfo->[0],
	    "lgpassword" => $userinfo->[1],
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
	    "lgname"     => $userinfo->[0],
	    "lgpassword" => $userinfo->[1],
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
	return $res_ref->{"query"}->{"tokens"}->{"csrftoken"};
    }else{
	die "Get error: $!\n";
    }
}

sub getContent {
    my $fn = shift;
    my $url = URI->new( $api_url );
    $url->query_form(
        "action" => "parse",
        "page"   => $fn,
        "prop"   => "wikitext",
        "formatversion" => 2,
        "format" => "json",
    );
    my $response = $browser->get($url);
    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
        my $wikitext = $res_ref->{"parse"}->{"wikitext"};
        return $wikitext;
    } else {
        return "";
    }
}

sub editPage {
    my $edit_token = shift;
    my $svg = shift;
    my $surl = shift;
    my $doi = shift;
    my $title = "File:${svg}";
    print $title, "\n";
    my $source = getContent($title);
    if (index($source, $doi) > -1){
        print "既にdoiが反映されています。\n";
        return 
    }
    substr($source, index($source, $surl), length($surl), $doi);
    print $source, "\n\n";

    my $url = URI->new( $api_url );
    my $response = $browser->post(
	$url,
	Content_Type     => "multipart/form-data",
	Content_Encoding => "utf-8",
	Content => [
	    "action"   => "edit",
	    "token"    => $edit_token,
	    "title"    => encode_utf8($title),
	    "text"     => encode_utf8($source),
	    "summary"  => encode_utf8("Change of source url."),
	    "format"   => "json",
	]);

    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
        print "Edit:", $res_ref->{"edit"}->{"result"}, "\n";
        if($res_ref->{"edit"}->{"result"} eq "Success"){
            open (my $log, ">>", "log.txt");
	    print "Edit successfully.\n";
	    print $response->content, "\n";
	    print $log $response->content, "\n";
            close($log);
        } else {
            print "Edit failed! Output was:\n";
            print $response->content, "\n";
        }
    }else{
        die "Post error: $!\n";
    }
}

sub csv_parse_and_edit {
    my $edit_token = shift;
    my $csv = shift;
    my ($svg, $url, $doi) = $csv->fields();       

    return 0 unless $svg;
    return 0 unless $url;
    return 0 unless $doi;

    editPage($edit_token, $svg, $url, $doi);

    return 1;
}

sub main {

    &initBrowser;
    my $edit_token = &loginAndGetToken;
    open(my $data, '<:utf8', $file);
    <$data>;
    while (<$data>) {
        next if /^#/;
        chomp;
        trim($_);
        my $result_code = 0;
        if ($csv->parse($_)) {
            $result_code = csv_parse_and_edit($edit_token, $csv);
        } else {
            warn "Parse error: $_\n";
        }
        if ($result_code > 0){
            sleep 3;
        }
    }
}

__END__
