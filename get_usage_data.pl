#!/usr/bin/env perl

=head

TogoPictureGalleryにあるイメージのうち、WikimediaCommonsに投稿してあるものの利用状況を取得する。
具体的には、WikimediaCommonsの下記のカテゴリに含まれるファイルが、ウィキメディア財団の管理するプロジェクトで使われている場合に、そのデータを取得する。

* Life_science_icons_from_DBCLS
* Life_science_images_from_DBCLS

サブカテゴリには対応していません。
API経由で取得出来るファイル情報やリンク数はカテゴリ毎、ファイル毎にそれぞれ最大500までという制限があり、予め特定のカテゴリに含まれるファイル数やリンク数を取得する方法が不明なので、今後、対応が必要になるかも知れません。
下記のパラメタが鍵と思われます。

list=categorymembers
cmcontinue: When more results are available, use this to continue.

prop=globalusage
gucontinue: When more results are available, use this to continue.

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

# action=query&list=categorymembers&cmtitle=Category:Life_science_icons_from_DBCLS&cmlimit=max&cmtype=file&format=json

sub getPageList {
    my $catname = shift;
    $catname = "Category:". $catname;
    my $url = URI->new( $api_url );
    $url->query_form(
	"action" => "query",
	"list" => "categorymembers",
	"cmtitle"  => $catname,
	"cmlimit" => "max",
	"cmtype" => "file",
	"format" => "json",
	);
    my $response = $browser->get($url);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	for ( @{ $res_ref->{"query"}->{"categorymembers"} } ){
	    getGlobalUsage($_->{"title"});
	    sleep 0.2;
	}
	return;
    }else{
	return;
    }
}

# action=query&prop=globalusage&titles=File:201704%20brain.svg
sub getGlobalUsage {
    my $fn = shift;
    my $url = URI->new( $api_url );
    $url->query_form(
	"action" => "query",
	"prop"  => "globalusage",
	"gulimit" => "max",
	"titles" => $fn, # eg "File:201703_tardigrade.svg"
	"format" => "json",
	);
    my $response = $browser->get($url);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	my $pages_ref = $res_ref->{"query"}->{"pages"};
	my $pageid = [ keys %{ $pages_ref } ]->[0];
	my $usage_ref = $pages_ref->{$pageid}->{"globalusage"};
	for ( @$usage_ref ){
	    print join("\t", ($fn, $_->{"wiki"}, $_->{"title"}, $_->{"url"})), "\n";
	}
	return;
    }else{
	return;
    }
}

initBrowser();
getPageList("Life_science_icons_from_DBCLS");
getPageList("Life_science_images_from_DBCLS");

__END__
