#!/usr/bin/perl -w
BEGIN {
	our $DataDir;
	our $ModuleDir;
	$DataDir = '.' unless($DataDir);
	$ModuleDir = "$DataDir/lib" unless($ModuleDir);
	unshift @INC,$ModuleDir;
	$ENV{NIGHTGUN_DEBUG} = 1;
}
use MyPlace::Encode qw/guess_encoding/;
use NightGun; #qw/NDEBUG/;
use NightGun::StoreLoader; 
use NightGun::App;
use CGI;
use Env qw/$SCRIPT_NAME $PATH_INFO/;
use URI::Escape;
NightGun::init($DataDir,$DataDir);
my $Worker = NightGun::StoreLoader->new();
my $History = NightGun::History->new($NightGun::Config);
my $Recents = NightGun::Recents->new($NightGun::Config);
my $q = CGI->new;
my $DocumentHeader = qq(<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN")
  . qq( "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">\n)
  . qq(<html xmlns="http://www.w3.org/1999/xhtml">);
my $REQUEST = uri_unescape($PATH_INFO ? $q->path_info : shift(@ARGV));
my $BASE_URL = $q->url() || $SCRIPT_NAME;

sub DoRequest {
	&load_store($REQUEST);
	&save_config;
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

sub TimeToRFC822 {
  my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime(shift); # Sat, 07 Sep 2002 00:00:01 GMT
  return sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT", qw(Sun Mon Tue Wed Thu Fri Sat)[$wday], $mday,
     qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)[$mon], $year+1900, $hour, $min, $sec);
}

sub GetHeader {
	my $title = shift;
	my $charset = shift(@_) || 'utf8';
  return $DocumentHeader
	. $q->head(
		$q->title($q->escapeHTML($title))
		. '<meta http-equiv="Content-Type" content="text/html; charset=' . $charset . '" />'
	  )
	. '<body>';
}

sub PrintFooter {
	my $title = shift;
	print $q->h3($title || $REQUEST);
	print $q->end_html;
}

sub load_store {
    my $path = shift;
    my $flag = shift or 0; ##### 0,undef = normal ; 1 = from_history_leaf
    NightGun::message(
		"load_store",$path
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
		NightGun::message("load_store","Unable to load $path");
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
    }
    if((!$flag eq 1) and  !$store->{leaf} and !$store->is_single and ($path !~ /\/$/) ) {
        NightGun::message("load_store","NO leaf,Try loading from history entry");
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
	
	print STDERR "path => $path\n";
	foreach(qw/root leaf parent id entry/) {
		print STDERR "$_ => $store->{$_} \n";
	}
	if((!$store->{leaf}) and @lists and $path !~ m/\/$/) {
		my %filesmap = @lists;
		my $default_file;
		foreach(values %filesmap) {
			if(m/(?:content|aaa|index)\.(?:html|htm|shtml)$/) {
				$default_file = $_;
				if($1 eq 'index') {
					last;
				}
			}
		}
		if($default_file) {
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
			save_store_state($store);
		}
		elsif(m/\.(?:jpg|jpeg)$/) {
			$filetype = 'raw';
			$mimetype = 'image/jpeg';
			save_store_state($store);
		}
		elsif(m/\.(png|gif)$/) {
			$filetype = 'raw';
			$mimetype = "image/$1";
			save_store_state($store);
		}
	}
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
		return;
	}

	if(!$store->{leaf}) {
		PrintList($store,$path,\@lists);
		return;
	}

	my $enc = guess_encoding($store->{data},1,'gbk');
	if($enc and (!($enc eq 'utf8'))) {
		$data = $enc->decode($data);
	}
	my $title = $store->{leaf};
	$title =~ s/^.+\///;
#	$title .= "::" . $store->{entry} if($store->{entry});
	#use Data::Dumper;die(Data::Dumper->Dump([$enc->name],['*enc']));
	print GetHeader($title,'utf-8');
	print $q->h1($title);
	print $q->start_div(-class=>'content');
	foreach my $line(split('\n',$data)) {
		print $q->p($line);
	}
	print $q->end_div;
	PrintFooter($title);
}

sub PrintList {
	my($store,$path,$lists) = @_;
	print GetHeader($path,'utf-8');
	print $q->h1($path . ':');
	print $q->start_div(-class=>'content') . $q->start_ul;
	my @maps = (@$lists);
	while(@maps) {
		my $name = shift @maps;
		my $url = shift @maps;
		print $q->li($q->a({-href=>"$BASE_URL$url"},$name));
	}
	print $q->end_ul . $q->end_div;
	PrintFooter($path);
}

sub save_store_state {
    my $store = shift;
    if($store->{leaf} and $store->{leaf} =~ m/[^\/\\]$/) {
        $History->add($store->{root},$store->{leaf});
    }
    return $store;
}


sub save_config {
	NightGun::saveConfig;
}

sub load_config {
	NightGun::loadConfig;
}

sub quit {
    &save_config;
}

sub parse_option {
	my $str = shift;
	my $parent = $str;
	my $child = "";
	if($str =~ m/^\/?(.+)::\/(.*)$/) {
		$parent=$1;
		$child=$2;
	}
	return ($parent,$child);
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


&DoRequest();
1;
