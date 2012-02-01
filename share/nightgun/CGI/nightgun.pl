#!/usr/bin/perl -w
BEGIN {
	use File::Spec::Functions qw/catfile catdir rel2abs curdir abs2rel/;
	our $DataDir;
	our $ModuleDir;
	$DataDir = curdir() unless($DataDir);
	$ModuleDir = catfile($DataDir,'lib') unless($ModuleDir);
	unshift @INC,$ModuleDir;
	$ENV{NIGHTGUN_DEBUG} = 1;
	$ENV{LANG} = 'en_US.UTF-8';
}
use strict;
use vars qw/
	$DataDir
	$ModuleDir
	$CSS
	%COPYRIGHT
	$COPYRIGHT
	$q
	$LOG_FILENAME
	$Worker
	$History
	$Recents
	$REQUEST_PATH
	$BASE_URL
	$UTF8
	$SCRIPT_NAME
	$PATH_INFO
	$LANG
	$REQUEST_URI
	$ISO8859
/;

use MyPlace::Encode qw/guess_encoding/;
use NightGun; #qw/NDEBUG/;
use NightGun::StoreLoader; 
use NightGun::App;
use CGI;
use URI::Escape;
use Encode qw/find_encoding from_to/;

my $FH_ERR;


sub DoRequest {
	use Data::Dumper;
	&Init;
	&DebugPrint(Data::Dumper->Dump([\%ENV],['*ENV']));
	&LoadStore($REQUEST_PATH);
	&Quit;
}

sub Init {
	&InitVariables;
	open $FH_ERR,'>&',\*STDERR;
	open STDERR,'>>',$LOG_FILENAME;
	NightGun::init($DataDir,$DataDir);
}

sub InitVariables {
	$SCRIPT_NAME = $ENV{SCRIPT_NAME};
	$PATH_INFO = $ENV{PATH_INFO};
	$LANG = $ENV{LANG};
	$REQUEST_URI = $ENV{REQUEST_URI};
	use Env qw/$SCRIPT_NAME $PATH_INFO $LANG/;
	$UTF8 = find_encoding('utf8');
	$ISO8859 = find_encoding('iso-8859-1');
	$Worker = NightGun::StoreLoader->new();
	$History = NightGun::History->new($NightGun::Config);
	$Recents = NightGun::Recents->new($NightGun::Config);
	$q = CGI->new;
	#$REQUEST_PATH = $UTF8->decode(($PATH_INFO ? $PATH_INFO : shift(@ARGV)));
	#$PATH_INFO = 
	#$REQUEST_PATH = $PATH_INFO ? $PATH_INFO : shift(@ARGV);
	$REQUEST_PATH = &Uri2Path($REQUEST_URI);
#	eval { $REQUEST_PATH = ($ISO8859->encode($UTF8->decode($REQUEST_PATH))) };
	$BASE_URL = $q->url() || $SCRIPT_NAME;
	$LOG_FILENAME = catfile($DataDir,'debug.log') unless($LOG_FILENAME);
	%COPYRIGHT = (
		NIGHTGUN=>$q->a({-href=>'http://nightgun.googlecode.com'},"NightGun"),
		MYPLACE=>$q->a({-href=>'mailto:xiaoranzzz@myplace.hell'},$q->strong("xiaoranzzz")),
		DATE=>'1981 - 2081',
		AUTHOR=>'xiaoranzzz@myplace.hell',
	) unless(%COPYRIGHT);
	
	$COPYRIGHT = "Power by &copy;$COPYRIGHT{NIGHTGUN} &copy;$COPYRIGHT{MYPLACE}, $COPYRIGHT{DATE}." unless($COPYRIGHT);
	$CSS = catfile($DataDir,'theme.css') unless($CSS);
}

sub Uri2Path {
	my $uri = shift;
	my $path = substr($uri,length($SCRIPT_NAME));
	$path = uri_unescape($path);
	return $path;
	if($ENV{'HTTP_ACCEPT_CHARSET'} =~ m/^\s*([^,]+)/) {
		my $charset = $1;
		eval {from_to($path,$charset,'iso-8859-1');};
	}
	return $path;
}

sub GetParam {
  my ($name, $default) = @_;
  my $result = $q->param($name);
  $result = $default unless defined($result);
  return QuoteHtml($result); # you need to unquote anything that can have <tags>
}

sub SetParam {
  my ($name, $val) = @_;
  $q->param($name, $val);
}

sub QuoteHtml {
  my $html = shift;
  $html =~ s/&/&amp;/g;
  $html =~ s/</&lt;/g;
  $html =~ s/>/&gt;/g;
  $html =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f]/ /g; # legal xml: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
  return $html;
}

sub DebugPrint {
	print STDERR @_;
	print FH_ERR @_;
	return @_;
}

sub ReadFile {
	my $file = shift;
	local $/ = undef;
	if(!open FI,"<",$file) {
		DebugPrint("Error open $file:$!\n");
		return undef;
	}
	binmode FI;
	my $buf = <FI>;
	close FI;
	return $buf;
}

sub TimeToRFC822 {
  my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime(shift); # Sat, 07 Sep 2002 00:00:01 GMT
  return sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT", qw(Sun Mon Tue Wed Thu Fri Sat)[$wday], $mday,
     qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)[$mon], $year+1900, $hour, $min, $sec);
}



sub GetHttpHeader {
  my ($type, $ts, $status,$charset) = @_; # $ts is undef, a ts, or 'nocache'
  my %headers = (-cache_control=>'max-age=10');
  $headers{'-last-modified'} = TimeToRFC822($ts) if $ts and $ts ne 'nocache'; # RFC 2616 section 13.3.4
  $headers{-type} = GetParam('mime-type', $type);
  $headers{-type} .= "; charset=$charset" if $charset;
  $headers{-status} = $status if $status;
  if ($q->request_method() eq 'HEAD') {
    print $q->header(%headers), "\n\n"; # add newlines for FCGI because of exit()
    exit; # total shortcut -- HEAD never expects anything other than the header!
  }
  return $q->header(%headers);
}

sub GetHeader {
	my $title = shift;
	my $charset = shift(@_) || 'utf8';
	return $q->start_html(
		-title=>$title,
		-encoding=>$charset,
		-head=>$q->meta({'http-equiv'=>'Content-Type','content'=>"text/html; charset=$charset"}),
		-style=>{code=>GetStyleSheet()},
		-author=>$COPYRIGHT{AUTHOR},
	);
}

sub PrintHeader {
	my $title = shift;
	my $charset = shift || 'utf-8';
	print GetHeader($title,$charset);
	print $q->start_div({'-class'=>'header'});
	print $q->h2($title);
	print $q->hr;
	print $q->end_div;
}


sub PrintFooter {
	my $title = shift;
	my $css = shift;
	print $q->style(GetStyleSheet()) if($css);
	print $q->start_div({-class=>'footer'});
	print $q->hr;
#	print $q->h3($title || $REQUEST_PATH);
	print $q->p({-class=>'copyright'},$COPYRIGHT);
	print $q->end_div;
	print $q->end_html;
}

sub StartContent {
	print $q->start_div({-class=>'content'});
	print @_ if(@_);
}
sub EndContent {
	print @_ if(@_);
	print $q->end_div;
}

sub GetStyleSheet {
	return '' unless(-f $CSS);
	return ReadFile($CSS) || '';
}

sub LoadStore {
    my $path = shift;
    my $flag = shift or 0; ##### 0,undef = normal ; 1 = from_history_leaf
    NightGun::message(
		"LoadStore",$path
	);
	my $store;
	my $to_parent;
	my $data;
	if($path =~ /^PARENT:/) {
		$path =~ s/^PARENT://;
		$to_parent=1;
	}
	$store = $Worker->load($path,1) unless($store);
	unless($store) {
		NightGun::message("LoadStore","Unable to load $path");
		return undef;
	}

    my @lists;
    if(!($store->is_single)) {
	    push @lists,"../",$store->{parent} if($store->{parent});
    	if($store->{dirs}) {
        	push @lists,
				map {my $t=$_;$t =~ s/\/$//g;$t =~ s/^.*\///;($t . "/",$_)}
					@{$store->{dirs}};
	    }
    	if($store->{files}) {
        	push @lists,
				map {my $t=$_;$t =~ s/^.*(:?\/|::)//;($t,$_)} @{$store->{files}};
	    }	
		eval {map {$_ = $UTF8->decode($_)} @lists;}
    }
    if((!$flag eq 1) and  !$store->{leaf} and !$store->is_single and ($path !~ /\/$/) ) {
        NightGun::message("LoadStore","NO leaf,Try loading from history entry");
        my @history_info = $History->get($store->{root});
		my $path = $history_info[0];
		if($path) {
			return print $q->redirect("$BASE_URL$path");
		}
    }
    if($store->{type} == $Worker->TYPE_URI) {
#        my $uri = $store->{data};
#        $uri = _to_gtk($uri) unless($store->{donot_encode});
#        $uri = uri_escape($uri,"%&") unless($store->{donot_escape});
#        $GUI->content_set_uri($uri);
    }
    else {
		$data = $store->{data};
    }
	
	#$path = $UTF8->encode($path);
	DebugPrint "path => $path\n";
	foreach(qw/root leaf parent id entry/) {
	#	$store->{$_} = $UTF8->encode($store->{$_});
		DebugPrint "$_ => $store->{$_} \n";
	}
	my %default_p = (
		toc=>100,
		aaa=>99,
		index=>98,
		content=>97,
	);

	if((!$store->{leaf}) and @lists and $path !~ m/\/$/) {
		my %filesmap = @lists;
		my $default_file;
		my $default_name;
		foreach(values %filesmap) {
			if(m/(?:content|aaa|index)\.(?:html|htm|shtml)$/) {
				if(!$default_file) {
					$default_file = $_;
					$default_name = $1;
				}
				elsif($default_p{$1} > $default_p{$default_name}) {
					$default_file = $_;
				}
			}
		}
		if($default_file) {
#			$default_file = $UTF8->encode($default_file);
			$default_file = uri_escape($UTF8->encode($default_file));
			$default_file =~ s/%2[fF]/\//g;
			$default_file =~ s/%3[aA]/:/g;
			DebugPrint 'redirect ' . "$BASE_URL$default_file\n";
			print $q->redirect("$BASE_URL$default_file");
			return;
		}
	}
	my $filetype = 'txt';
	my $mimetype = 'text/html';
	if($store->{leaf}) {
		if(-d $store->{root} and -f $store->{leaf} and !$data) {
			open FI,'<',$store->{leaf};
			$data = $store->{data} = join("",<FI>);
			close FI;
		}
		my $_ = $store->{leaf};
		if(m/\.(?:html|htm|shtml|xhtml)$/i) {
			$filetype = 'html';
			SaveState($store);
		}
		elsif(m/\.(?:jpg|jpeg)$/) {
			$filetype = 'raw';
			$mimetype = 'image/jpeg';
			SaveState($store);
		}
		elsif(m/\.(png|gif)$/) {
			$filetype = 'raw';
			$mimetype = "image/$1";
			SaveState($store);
		}
	}
	my $title = $store->{leaf} || $store->{root};
	if($title =~ m/([^\/]+::\/.*)$/) {
		$title = $1;
	}
	elsif($title =~ m/([^\/]+)\/?$/) {
		$title = $1;
	}
	#$title =~ s/\/+$//;
	#$title =~ s/^.+\///;
	eval {$title = $UTF8->decode($title);};
	DebugPrint "filetype=>$filetype\nmimetype=>$mimetype\n";
	DebugPrint "length of data=>" . length($data) . "\n";
	DebugPrint "title=>$title\n";
	print GetHttpHeader($mimetype,undef,undef,'IDONTCARE');#,'UTF-8');#GetParam('mime-type',$mimetype));
	if ($q->request_method() eq 'HEAD') {
		return;
	}

	if($filetype eq 'raw') {
		print $store->{data};
		return;
	}

	if($filetype eq 'html') {
		print $store->{data};
		PrintFooter($title,1);
		return;
	}
	if($path =~ m/\/$/) {
		PrintList($title,$path,\@lists);
		return;
	}
	if((!$store->{leaf}) and (!$store->{data} or !$store->{entry}) ) {
		PrintList($title,$path,\@lists);
		return;
	}
	my $title_enc = $title;
	my $enc = guess_encoding($store->{data},1,'gbk') if($store->{data});
	if($enc and (!($enc eq 'utf8'))) {
		$title_enc = $enc->encode($title);
	}
	else {
		$enc = $UTF8;
	}
	PrintHeader($title_enc,$enc->name);
	StartContent();
	foreach my $line(split('\n',$data)) {
		print $q->p($line);
	}
	EndContent();
	PrintFooter($title_enc);
}

sub PrintList {
	my($title,$path,$lists) = @_;
	PrintHeader($title || $path);
	StartContent($q->h3("Files:") . $q->start_ul(-class=>'list'));
	my @maps = (@$lists);
	while(@maps) {
		my $name = shift @maps;
		my $url = shift @maps;
		print $q->li($q->a({-href=>"$BASE_URL$url"},$name));
	}
	EndContent($q->end_ul);
	PrintFooter($title || $path);
}

sub SaveState {
    my $store = shift;
    if($store->{leaf} and $store->{leaf} =~ m/[^\/\\]$/) {
        $History->add($store->{root},$store->{leaf});
    }
    return $store;
}


sub SaveConfig {
	NightGun::saveConfig;
}

sub LoadConfig {
	NightGun::loadConfig;
}

sub Quit {
    &SaveConfig;
}

&DoRequest();
1;
