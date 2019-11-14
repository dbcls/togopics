#!/usr/bin/env perl

=head

TogoPictureGalleryにあるイメージのうち、WikimediaCommonsに投稿してあるものの利用状況を取得する。
具体的には、WikimediaCommonsの下記のカテゴリに含まれるファイルが、ウィキメディア財団の管理するプロジェクトで使われている場合に、そのデータを取得する。

* Life science icons from DBCLS
* Life science images from DBCLS

サブカテゴリには対応していません。

=cut

use strict;
use warnings;
use Fatal qw/open/;
use utf8; 
use LWP::UserAgent;
use LWP::Protocol::https;
use JSON::XS;
use Time::HiRes qw/sleep/;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my $browser;
my $ua = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:22.0) Gecko/20100101 Firefox/22.0";
my $api_url = "https://commons.wikimedia.org/w/api.php";
my $author = "DataBase Center for Life Science (DBCLS)";

sub initBrowser {
    $browser = LWP::UserAgent->new( agent => $ua );
    $browser->default_header( 'Accept-Language' => 'en-US' );
    $browser->default_header( 'Accept-Charset' => 'iso-8859-1,*,utf-8' );
    $browser->default_header( 'Accept' => '*/*' );
    $browser->cookie_jar( {} );
}

### Not used now.
sub getFileCount {
    my $catname = shift;
    $catname = "Category:". $catname;
    my $url = URI->new( $api_url );
    $url->query_form(
	"action" => "query",
	"prop" => "categoryinfo",
	"titles"  => $catname,
	"format" => "json",
	);
    my $response = $browser->get($url);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	my $pages_ref = $res_ref->{"query"}->{"pages"};
	my $pageid = [ keys %{ $pages_ref } ]->[0];
	my $count = $pages_ref->{$pageid}->{"categoryinfo"}->{"files"};
	return $count;
    }else{
	return "";
    }
}

# action=query&list=categorymembers&cmtitle=Category:Life_science_icons_from_DBCLS&cmlimit=max&cmtype=file&format=json
sub getPageList {
    my $catname = shift;
    $catname = "Category:". $catname;
    my $cmcontinue = "";
    my $count = 0;
    my $max_count = 500;
    while(1){
	my $url = URI->new( $api_url );
	if ($cmcontinue){
	    $url->query_form(
		"action" => "query",
		"list" => "categorymembers",
		"cmtitle"  => $catname,
		"cmlimit" => $max_count,
		"cmcontinue" => $cmcontinue,
		"cmtype" => "file",
		"format" => "json",
		);
	} else {
	    $url->query_form(
		"action" => "query",
		"list" => "categorymembers",
		"cmtitle"  => $catname,
		"cmlimit" => $max_count,
		"cmtype" => "file",
		"format" => "json",
		);
	}
	my $total = 0;
	my $response = $browser->get($url);
	if( $response->is_success ){
	    my $res_ref = decode_json $response->content;
	    my $iscontinue = $res_ref->{"continue"};
	    if (defined $iscontinue){
		$cmcontinue = $iscontinue->{"cmcontinue"};
	    }
	    for ( @{ $res_ref->{"query"}->{"categorymembers"} } ){
		$total++;
		getGlobalUsage($_->{"title"});
	    }
	}else{
	}
	last if $total < $max_count;
	sleep 0.2;
    }
}

# action=query&prop=globalusage&titles=File:201704%20brain.svg
sub getGlobalUsage {
    my $fn = shift;
    my $gucontinue = "";
    my $count = 0;
    my $max_count = 500;
    while(1){
	my $url = URI->new( $api_url );
	if ($gucontinue){
	    $url->query_form(
		"action" => "query",
		"prop"  => "globalusage",
		"gulimit" => $max_count,
		"gucontinue" => $gucontinue,
		"titles" => $fn, # eg "File:201703_tardigrade.svg"
		"format" => "json",
		);
	} else {
	    $url->query_form(
		"action" => "query",
		"prop"  => "globalusage",
		"gulimit" => $max_count,
		"titles" => $fn,
		"format" => "json",
		);
	}
	my $total = 0;
	my $response = $browser->get($url);
	if( $response->is_success ){
	    my $res_ref = decode_json $response->content;
	    my $iscontinue = $res_ref->{"continue"};
	    if (defined $iscontinue){
		$gucontinue = $iscontinue->{"gucontinue"};
	    }
	    my $pages_ref = $res_ref->{"query"}->{"pages"};
	    my $pageid = [ keys %{ $pages_ref } ]->[0];
	    my $usage_ref = $pages_ref->{$pageid}->{"globalusage"};
	    $total = scalar @$usage_ref;
	    for ( @$usage_ref ){
		print join("\t", ($fn, $_->{"wiki"}, $_->{"title"}, $_->{"url"})), "\n";
	    }
	}else{
	}
	last if $total < $max_count;
	sleep 0.2;
    }
}

initBrowser();
getPageList("Life science icons from DBCLS");
getPageList("Life science images from DBCLS");

__END__
