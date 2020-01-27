#!/usr/bin/env perl

=head

This script uploads images of Togo Picture Gallery to Wikimedia Commons.
Input file is "TogoPics.csv", which is maintained by the DBCLS Togo Picture Gallery team.

http://togotv.dbcls.jp/ja/pics.html

Yasunori Yamamoto @ Database Center for Life Science

Acknowledgements:
    This script uses parts of the upload.pl rev. 1.3.2 developed by Nicholas:~ Wikipedia: [[en:User:Nichalp]],
    which is published under the GPLv3 licence.

文字コード判別器用にここに非ASCII文字を記述しておきます。
下記項目を含む、それ以前のファイルはpngでアップロードしている。
462	242			togopic.2016.24	201611	コロモジラミ	human body louse
=cut

use strict;
use warnings;
use Fatal qw/open/;
use utf8; 
use LWP::UserAgent;
use LWP::Protocol::https;
use Net::FTP;
use Encode;
use Text::CSV_XS;
use Term::ReadKey;
use HTTP::Request::Common;
use JSON::XS;
use FindBin qw($Bin);
use Text::Trim;
use RDF::Trine::Store::SPARQL;
use Data::Dumper;
use constant EP => "https://query.wikidata.org/sparql";

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my %not_upload = map {$_ => 1} qw/513 514/;
my $image_dir = "$Bin/image_files";
my $csv = Text::CSV_XS->new({ binary => 1 });
my $file = 'TogoPics.csv';

# $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;

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

sub setupJEdictionary {
    open(my $dic, "<:utf8", $Bin."/Jpn2Eng.txt");
    while(<$dic>){
        chomp;
	my ($j, $e) = split /:/;
	$j2e{$j} = $e;
    }
    close($dic);
}

sub downloadImage {
    my $ftp;
    unless($ftp = Net::FTP->new($togopic_ftphost, Debug => 0, Passive => 1)){
	print "Cannot connect to $togopic_ftphost: $@";
	$ftp->quit;
	return 1;
    }
    unless($ftp->login("anonymous",'-anonymous@')){
	print "Cannot login: ", $ftp->message;
	$ftp->quit;
	return 1;
    }
    unless($ftp->cwd($togopic_ftppath)){
	print "Cannot change working directory: ", $ftp->message;
	$ftp->quit;
	return 1;
    }
    unless($ftp->get($_[0], $image_dir. "/". $_[0])){
	print "get failed ($_[0]): ", $ftp->message;
	$ftp->quit;
	return 1;
    }
    $ftp->quit;
    return 0;
}

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

sub getEntityID {
    my $fn = shift;
    $fn = "File:".$fn;
    my $url = URI->new( $api_url );
    $url->query_form(
	"action" => "wbgetentities",
	"sites"  => "commonswiki",
	"titles" => $fn, # eg "File:201703_tardigrade.svg"
	"format" => "json",
	);
    my $response = $browser->get($url);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	my $eid = [ keys %{$res_ref->{"entities"}} ]->[0];
	return $eid;
    }else{
	return "";
    }
}

sub getEntityStatements {
    my $fn = shift;
    $fn = "File:".$fn;
    my $url = URI->new( $api_url );
    $url->query_form(
	"action" => "wbgetentities",
	"sites"  => "commonswiki",
	"titles" => $fn, # eg "File:201703_tardigrade.svg"
	"format" => "json",
	);
    my $response = $browser->get($url);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	my $eid = [ keys %{$res_ref->{"entities"}} ]->[0];
	if( defined( $res_ref->{"entities"}->{$eid}->{"missing"} ) ){
	    return "";
	}elsif( defined( ref($res_ref->{"entities"}->{$eid}->{"statements"}) eq "ARRAY" ) ){
	    return "";
	}else{
	    my $value = $res_ref->{"entities"}->{$eid}->{"statements"}->{"P180"}->[0]->{"mainsnak"}->{"datavalue"}->{"value"};
	    while(my ($k, $v) = each %$value){
	    	print join("\t", ($fn, $k, $v)), "\n";
	    }
	}
    }else{
	die "Get error: $!\n";
    }
}

# api.php?action=wbcreateclaim&entity=Q42&property=P9003&snaktype=value&value={"entity-type":"item","numeric-id":1}
sub setClaims {
    my $eid = shift;
    my $qid = shift;
    my $edit_token = shift;
    if( existClaim($eid, "P180", $qid) > 0){
	print "Already stated: ", join("\t", ($eid, "P180", $qid)), "\n";
	return;
    }
    $qid =~ s/^Q//;
    my $value = encode_json {
	"entity-type" => "item",
	"numeric-id" => $qid,
	"id" => "Q${qid}"
    };
    my $url = URI->new( $api_url );
    my $response = $browser->post(
	$url,
	Content_Type     => "multipart/form-data",
	Content_Encoding => "utf-8",
	Content => [
	    "action"   => "wbcreateclaim",
	    "entity"   => $eid,
	    "property" => "P180",
	    "snaktype" => "value",
	    "value"    => $value,
	    "summary"  => "Added structured data.",
	    "token"    => $edit_token,
	    "format"   => "json",
	]);
    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
	if ($res_ref->{'success'}){
	    print "setClaims [${eid}]: Q${qid}\n";
	}elsif( defined($res_ref->{'error'}) ){
	    print "Error [$eid]: ", $res_ref->{'error'}->{'info'}, "\n";
	}else{
	    print Dumper $res_ref, "\n";
	}
    }else{
	die "Post error: $!\n";
    }
}

sub setLabel {
    my $title = shift;
    my $label = shift;
    my $lang = shift;
    my $edit_token = shift;
    my $url = URI->new( $api_url );
    my $response = $browser->post(
	$url,
	Content_Type     => "multipart/form-data",
	Content_Encoding => "utf-8",
	Content => [
	    "action"   => "wbsetlabel",
	    "site"     => "commonswiki",
	    "title"    => "File:".$title,
	    "value"    => $label,
	    "language" => $lang,
	    "summary"  => "Added a label (".$lang.").",
	    "token"    => $edit_token,
	    "format"   => "json",
	]);
    if( $response->is_success ){
        my $res_ref = decode_json $response->content;
	print "setLabel:",decode_utf8($label), "\n";
    }else{
	die "Post error: $!\n";
    }
}

# https://commons.wikimedia.org/w/api.php?action=wbgetclaims&entity=M57116616
sub getClaims {
    my $eid = shift;
    my $url = URI->new( $api_url );
    $url->query_form(
	"action" => "wbgetclaims",
	"entity" => $eid,
	"format" => "json",
	);
    my $response = $browser->get($url);
    if( $response->is_success ){
	my $res_ref = decode_json $response->content;
	if (my $claims = $res_ref->{'claims'}){
	    return $claims;
	}elsif (defined($res_ref->{'error'})){
	    return undef;
	}
    }else{
	return undef;
    }
}

sub existClaim {
    my $eid = shift;
    my $pid = shift;
    my $qid = shift;
    my $claims = getClaims($eid);
    if(! defined($claims)){
      return 0;
    }
    while(my ($k, $v) = each %$claims){
	next if $k ne $pid;
	for my $value ( @{ $claims->{$k} } ){
	    if($value->{'mainsnak'}->{'datavalue'}->{'value'}->{'id'} eq $qid){
		return 1;
	    }
	}
    }
    return 0;
}

sub getTaxQid {
    my $taxid = shift;
    my $qid = "";
    my $wd = RDF::Trine::Store::SPARQL->new( EP );
    my $query = 'SELECT ?____ ?QID WHERE { ?____ wdt:P685 ?NCBI_Taxonomy_ID.  BIND("'
                . $taxid
                . '" AS ?NCBI_Taxonomy_ID) BIND(SUBSTR(STR(?____), 32 ) AS ?QID) }';
    my $iterator = $wd->get_sparql( $query );
    if(my $row = $iterator->next) {
        $qid = $row->{ 'QID' }->value;
    }
    return $qid;
}

sub uploadFile {

    my $p = shift;
    open (my $log, ">>", "log.txt");
    my $full_description = $p->{"description"};
    my $mastercategory = join("\n", map {"[[Category:$_]]"} @{$p->{tags}});
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

# Begin optional template integration
    my $metadata = $information;
    if (defined $p->{"other_information"}) {
	$metadata .= "\n". $p->{"other_information"}. "\n";
    };

# Integrating remaining templates into one 
    $metadata .="\n== [[Commons:Copyright tags|Licensing]] ==\n$licence\n{{LicenseReview}}\n\n$mastercategory\n\n";

    print "Metadata\n$metadata";

    my $description = $p->{"description"};
    my $current_name = $p->{"current_name"};

    print "Uploading $current_name to the Wikimedia Commons. \nDescription: ";
    print $description, "\n";

    my $url = URI->new( $api_url );
    my $response = $browser->post(
	$url,
	Content_Type     => "multipart/form-data",
	Content_Encoding => "utf-8",
	Content => [
	    "action"   => "upload",
	    "filename" => $p->{"original_svg"},
	    "file"     => ["$current_name"],
	    #"url"     => $source,
	    "token"    => $p->{"token"},
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

#    &setupJEdictionary;
    &initBrowser;
    my $edit_token = &loginAndGetToken;

    open(my $data, '<:utf8', $file);
    <$data>;
    while (<$data>) {
	last if /^#/;
	chomp;
	trim($_);
	if ($csv->parse($_)) {
	    my ($picture_id, $togopic_id, $taxicon_id, $update, $doi, $date,
		$title_jp, $title_en, $scientific_name, $tax_id, $tag, $original_png,
		$original_svg, $original_ai, $DatabaseArchiveURL) = $csv->fields();       

	    next unless $picture_id;
	    next if $not_upload{$picture_id};
	    unless($original_svg){
		warn "No svg file for the ID: ${picture_id}\n";
		next;
	    }
	    $togopic_id ||= 0;
	    $taxicon_id ||= 0;
	    next if $taxicon_id > 0;
	    $doi //= "";
	    $date //= "";
	    $title_jp //= "";
	    $title_en //= "";
	    $scientific_name //= "";
	    $tax_id //= "";
	    $tag //= "";
	    $original_png //= "";
	    my $description = "{{en|$title_en}}{{ja|$title_jp}}";
	    next if downloadImage($original_svg);
	    my $current_name = $image_dir. '/'. $original_svg;
	    my $source = $togopic_root. $doi. ".html";
	    my $other_info = length($tax_id) > 0 ? "Tax ID:". $tax_id : "";
	    my @tags = map {$j2e{$_}} grep {$j2e{$_}} split /,/, $tag;
	    unshift @tags, "Biology";
	    push @tags, $scientific_name if $scientific_name && $scientific_name ne "-";
	    if($tag eq "臓器"){
		(my $another_category = $title_en) =~ s/^([a-z])/uc($1)/e;
		$another_category =~ y/ /_/;
		$another_category =~ s/_?\(.*$//;
		push @tags, $another_category;
	    }
	    if($taxicon_id > 0){
		push @tags, "Taxonomy icons by NBDC";
	    }elsif($togopic_id > 0){
		push @tags, "Life science images from DBCLS";
	    }

	    # uploadFile(
	    # 	{
	    # 	    "token"        => $edit_token,
	    # 	    "date"         => $date,
	    # 	    "description"  => $description,
	    # 	    "current_name" => $current_name,
	    # 	    "source"       => $source,
	    # 	    "original_svg" => $original_svg,
	    # 	    "tags"         => \@tags,
	    # 	    "other_information" => $other_info,
	    # 	    "other_version1"    => "",
	    # 	    "other_version2"    => "",
	    # 	});

	    setLabel($original_svg, $title_en, "en", $edit_token);
	    setLabel($original_svg, encode_utf8($title_jp), "ja", $edit_token);
	    if($tax_id ne '-'){
		my $qid = getTaxQid($tax_id);
		if($qid){
		    my $eid = getEntityID($original_svg);
		    if($eid){
			setClaims($eid, $qid, $edit_token);
		    }
		}
	    } else {
	    }

	} else {
	    warn "Parse error: $_\n";
	}

	sleep 2;

    }
}

__END__
