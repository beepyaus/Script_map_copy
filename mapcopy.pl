#!/usr/bin/env perl

use v5.32;
use Modern::Perl '2015';
use XML::LibXML;

# use autodie;
# use warnings;
# use strict; 

#############OR this.. ######################
#use 5.016; # implies "use strict;"
#use warnings;
#use autodie;
#############################################

#####################################################
# part 1. 
#   - should of cp-ed the base and specific base_variant dir into the swap dir
#   - re-created the failsafe default http website pages 
#   - NO chown should be done yet as Vagrant ( or Docker ) does not have permission to chown the 'troy' user owned files 
#
# part 2 - this file 
#   - chown the swap/temp dir to correct ACLs etc 
#   - use the XML spec file for lookup 
#
#to be run on PROD/AWS EC2 or Vagrant only

#perform rsync or similar on all the required dirs/files into the target (normally LIVE/PROD) server!!!
#####################################################

#usage: mapcopy.pl --dry-run --mode MODE --force-yes
say "";
say "_____________________________________________________________";
say "__________________mapcopy.pl (Perl5)_________________________";
say "";

my $_VERSION = "1.10"; 
my $_DEBUG = 1; #show 'say' debug lines. 

my $mode = ""; 
my $forceYes = 0;
my $dryrun = 0;

while (@ARGV) { #while not empty.
    my $x = $ARGV[0]; 
    if ($x =~ m/--dry-run|-d/ ) { $dryrun = 1; } 
    if ($x =~ m/--mode|-m/ ) { $mode = $ARGV[1]; } 
    if ($x =~ m/--force-yes|-f/ ) { $forceYes = 1; } 
    if ($x =~ m/--help|-h/) { showHelp(); } 
    if ($x =~ m/--version|-v/) { showVersion(); } 
    shift @ARGV; #remove the first item and carry on. 
}

debug( "ARG: mode = $mode" );
debug( "ARG: forceYes = $forceYes"); 
debug( "ARG: dryrun = $dryrun" ); 

if ( $dryrun == 1 ) {
    $dryrun=" --dry-run ";
    say "Running in DRY-RUN mode for rsync, no changes saved!!!";
}else {
    $dryrun = ""; #very important, else "0" would be directly inputted to rsync call! 
}

if ( 'live' eq $mode ) { 
    say "Running in LIVE mode for rsync! ";  
    say "NOTE: currently (Fri 04 Nov 2022 14:46:52) this has NO affect.";
} 

#Hardcoded value to prefix the target destination for testing
my $TEST_PREFIX = '/home/troy/Downloads/perl_test_mapcopy';
#my $TEST_PREFIX = '';

debug( "TEST_PREFIX:  $TEST_PREFIX " );

#store the common variables from common shell script
my %fields = getBase();  

#global vars
my $swapdir = $fields{'swapdir'};
my $target = $fields{'target'};
my $buildname = $fields{'buildname'};
my $backupdir="${swapdir}/base_backup_BUILD_${target}";
my $builddir = $fields{'build_dir'};
my $logfiledir="${swapdir}/rsync_log";

#changed from...
#my $sourcedir="${swapdir}/${buildname}";
#changed to.. as build dir is NOW cp's over to the /tmp dir initially
my $sourcedir = $builddir;

if ($target eq "NULL" || $target eq "" ){
    say "ERROR: target is NULL or empty. ";
    say "Terminating process"; 
    say "Probably running on the bare metal dev machine. this is a no-no. ";
    exit 1;
}

#recursive added map of each file and dir
#xml treespec version
my %fileMap; 

#recursive added map of each file and dir 
#filesystem version
my %fileSourceMap;

cleanBackupDir($backupdir);
setupLogfileDir($logfiledir);
#2nd param: boolean: delete extra files in target, 

my $webowner="http"; 
if ( isPlatform('Alpine') ) {
    $webowner="apache";
}elsif ( isPlatform('OpenBSD') ) {
    $webowner="www"
}else{
    $webowner="http"
}

simpleCopy ("/var/www/html/sites/default" , 0, $webowner, $webowner );  
simpleCopy ("/var/www/html/sites/default_http" , 0, $webowner, $webowner );  
simpleCopy ("/var/www/html/sites/default_https" , 0, $webowner, $webowner );  
mapCopy ("/etc/httpd/conf" , 0 );  
mapCopy ("/etc/apache2" , 0 );  
mapCopy ("/etc/postfix" , 0 );  
mapCopy ("/etc/postgresql" , 0 );  
mapCopy ("/etc/php" , 0 );  
mapCopy ("/etc/php8" , 0 );  
mapCopy ("/var/lib/postgres" , 0 );  
mapCopy ("/var/lib/postgresql" , 0 );  
mapCopy ("/root", 0 );  
mapCopy ("/home/vagrant", 0 );  
mapCopy ("/home/arch", 0 );  
mapCopy ("/home/alpine", 0 );  
mapCopy ("/etc/logrotate.d" , 0 );  
simpleCopy ("/etc/redis.conf" , 0, 'redis', 'redis' );  #TODO: all these mapcopy params can be sourced when the text config file
simpleCopy ("/etc/ssl_self" , 0, 'root', 'root' );  #TODO: all these mapcopy params can be sourced when the text config file
simpleCopy ("/etc/letsencrypt" , 0, 'root', 'root' );  #TODO: all these mapcopy params can be sourced when the text config file


##################sub declarations######################################
sub debug{
    my ($params) = @_; 
    if ( $_DEBUG == 1 ){
        say "DEBUG: $params";
    }
}

sub showVersion{
    say "mapcopy.pl V${_VERSION}";
    die();
}

sub showHelp{
say "Perl Script version of project_tree"; 
say ""; 
say "usage: mapcopy.pl PARAMS"; 
say ""; 
say "PARAMS: 
        -d, --dry-run 
            dryrun mode: rsync uses --dry-run switch OR prepend 'echo' for command call. 
            e.g. echo rm -rf foo_dir 
        
        -m, --mode [live|dev|other] 
            production or other. NOTE 'live' is checked against!
        
        -f, --force-yes
            force a 'yes/y' for STDIN user input
";
#MUST kill as its only a help page. 
die();

}

sub getPlatform{
    my $uname = "uname -a"; 
    my $ret = qx/$uname/; 
    return $ret; 
}

sub isPlatform{
    my ($testplatform) = @_; 
    my $uname = "uname -a"; 
    my $ret = qx/$uname/; 
    say "isPlatform: uname -a: $ret"; 
    if ( $ret =~ m/$testplatform/ ) {
        say "isPlatform: $testplatform is true ";
        return 1; 
    }
    return 0; 
}

sub getBase{
#the bash script must output the var as 
#foo: value
#foo: value 
#..and the perl script will parse that
    my %_fields;
    my $hostname = "";  #intentionally empty unless we need to be explicit.
    #say "zero = $runtime_name" ;

    #TODO: move all this out , by using /usr/bin/env sh 
    #for the base_setup.sh to know/use the path etc .

    my $cmd_path = "dirname $0"; #zero is name of this perl script!
    my $runtime_path = qx/$cmd_path/;
    say "Result of dirname \$0 (before line strip) : $runtime_path"; 
    $runtime_path =~ s/\n.*//s; #strip out \n 

    #say "runtime_path = XX $runtime_path YY"; 
    my $self_path = "${runtime_path}/base_setup.sh"; 
    say "self_path : $self_path" ;

    #-h $hostname 
    #above switch NOT used. unless needed in future. 
    my $cmd = "${runtime_path}/base_setup.sh -s $self_path" ; 
    say "Calling: base_setup.sh = $cmd" ; 

    my @basevars = qx/$cmd/;

    for my $var (@basevars){
        $var =~ /^(.*?): (.*)$/; # Pre–colon text into $1, post–colon into $2
        $_fields{$1} = $2;
    }

    say "variables from base_setup.sh...";
    while ( my ($key, $value) = each %_fields) {
        say "key:$key, value:$value";
    }
    return %_fields;
}

sub setupLogfileDir{
    my ($logfiledir) = @_;
    say "setupLogfileDir:  logfiledir: $logfiledir";
    say " ...mkdir call: ";
    ##CAUTION: OpenBSD does NOT have '-v' args for mkdir !!!!
    say qx/mkdir -p $logfiledir /;
}


sub cleanBackupDir {
#setup and clean out backup dir for next processing...
    my ($backupdir) = @_;
    say "CleanBackupDir: backupdir: $backupdir "; 
    my $cmd='';
    my $result=0;
    if ($backupdir eq '/'){
        say "ERROR: backupdir is root! exit!";
        return -1;

    }else{
        $cmd = "rm -rf $backupdir ";
        $result = qx/$cmd/;
        say "CleanBackupDir: remove dir result : $result";

        #CAUTION: OpenBSD doesnt have -v args for mkdir
        $cmd = "mkdir -p $backupdir "; 
        $result = qx/$cmd/;
        say "CleanBackupDir: mkdir result : $result";
    }
}


sub fileData{
#looks silly, but incase need to add something to do a test etc, just keep as a sub
    my ( $level, $type, $user, $group, $mode, $default_file_user, $default_file_group, $default_file_mode ) = @_;
    return ($level, $type, $user, $group, $mode, $default_file_user, $default_file_group , $default_file_mode) ;
}


sub scanTree{
#Recurse/iterate into each dir and create a hashtable of all the files/dirs to 
#compare against the filesystem candidate to be uploaded. 
    my ($curpath, $curdir, $level,
        $parent_default_file_user, 
        $parent_default_file_group, 
        $parent_default_file_mode) = @_; 

    #either it's own settings or go to the parents value . so it trickles down ...  
    my $defaultFileMode = ($curdir->getAttribute('default_file_mode') // '') || $parent_default_file_mode;
    my $defaultFileUser = ($curdir->getAttribute('default_file_user') // '') || $parent_default_file_user;
    my $defaultFileGroup = ($curdir->getAttribute('default_file_group') // '') || $parent_default_file_group;

    # say "def fm = $defaultFileMode";
    # say "def fu = $defaultFileUser";
    # say "def fg = $defaultFileGroup";

    $fileMap{$curpath} = [ fileData ( $level, 'd', 
            $curdir->getAttribute('user') // '' , 
            $curdir->getAttribute('group') // '',
            $curdir->getAttribute('mode') // '', 
            $defaultFileUser, $defaultFileGroup, $defaultFileMode )];
   
    foreach my $node ($curdir->nonBlankChildNodes) {
        unless ($node->nodeType == XML_ELEMENT_NODE ){
            say "ERROR: Node not an element! nodeType: $node->nodeType ";
            next; 
        }
        #they all should be elements, the DOM may return something else, if so this needs to be considered.  
        if ($node->nodeName eq 'directory') {
            scanTree( $curpath.'/'.$node->getAttribute('name'), $node, $level+1,
                        $defaultFileUser, $defaultFileGroup , $defaultFileMode ); 
        
        }elsif ($node->nodeName eq 'file') {
            $fileMap{ $curpath.'/'.$node->getAttribute('name') } = 
                    [ fileData( $level , 'f'
                        , $node->getAttribute('user') // '' 
                        , $node->getAttribute('group') // '' 
                        , $node->getAttribute('mode') // ''
                        , $defaultFileUser, $defaultFileGroup , $defaultFileMode )]; 
        }else {
            say "ERROR Unexpected node name. nodeName: $node->nodeName ";
        }
    }#end for

}#end sub

sub simpleCopy{
    #simple rsync version just for default-website for e.g , no xml tree etc 
    #and signular file transfer 
    my($pathdir, $delete, $user, $group) = @_;
   
    my $source =  $sourcedir . $pathdir;
    say "simpleCopy: source: $source "; 

    #TODO: there IS a global var named target!! see perl rules for accessing vars etc 
    my $target = $TEST_PREFIX . $pathdir;
    my $res = ''; 

    if (-e $source){

        if (-d $source){
            # Add the slash to start copying the contents that follows the end dir and NOT the dir itself
            $source .= '/'; 
            #CAUTION: OpenBSD does not do -v on mkdir!!
            my $mkdir = "mkdir -p $target ";
            $res = qx/$mkdir/;
            say "simpleCopy: mkdir -p \'$target\'  result: \'$res\' ";
        }

    }else {
        say "simpleCopy: Error: \'$source\' does not exist!";
        return -1;
    }

    my $logfilepart = $pathdir; 
    $logfilepart =~ s/\//\_/g;

    my $chown =  (defined $user && defined $group ) ? " --chown=${user}:${group} " : "" ; 
    my $rsync_delete = $delete ? " --delete " : "" ; 
    my $rsync_backup=" --backup --backup-dir=${backupdir}${pathdir} " ;
    my $rsync_logfile=" --log-file=$logfiledir/${logfilepart}_" . time() . ".log ";
    my $rsync_switches = " $dryrun -v -a --human-readable  $rsync_delete $chown $rsync_backup $rsync_logfile";
    my $rsync = "rsync $rsync_switches $source $target ";
    
    say "RSYNC: to be run: \"$rsync\" " ;
    $res = qx/$rsync/;
    say "simpleCopy: rsync result: \"$res\" "; 
}

sub mapCopy {
# open a xml tree spec to get mode/user/group etc 
# recurse into all directory elements to get all file elements etc 
# populate the hash tree with the full file path for easy lookup 
#pass over to copysourcefiles with delete param for rsync to decide if to rm extra files NOT in source dir.  
    my($pathdir, $delete) = @_;

    if (! -e $pathdir){
        say "############################################";
        say "Pathdir parameter '$pathdir' not found on filesystem.  ";
        say "Not performing mapcopy!";
        say "############################################";
        return -1; 
    }
    ##################
    #TODO: turn into params 
    undef %fileMap ;
    undef %fileSourceMap;

    ################

    my $filepart = $pathdir; 
    #replace / . with _ chars 
    $filepart =~ s/[\/\.]/\_/g;
    my $filename = "$fields{'configdir'}/tree_definitions/spec${filepart}.xml";

    say "XML Spec Treefile: $filename ";
    if (! -e $filename){
        say "File spec '$filename' not found.";
        return -1; 
    }

    open my $fh, '<', $filename ;
    binmode $fh; # drop all PerlIO layers possibly created by a use open pragma
    my $doc = XML::LibXML->load_xml(IO => $fh);
    my $tree = $doc->documentElement;
    #should only be ONE MAIN DIR/ROOT DIR
    my ($maindir) = $tree->getChildrenByTagName('directory');
    
    scanTree($maindir->getAttribute('name') , $maindir, 0, '','','');

    #now scan source file dir created hashtable. 
    #recusrse into real build directory and cross-ref the mode/user/group from the hashtable. 
    scanSource($pathdir); 
    copySourceFiles($pathdir, $delete);
}

sub copySourceFiles{
#re-chmods the files/dirs that are in the preset TMP dir --NOT the target files 
#re-chowns the '' '' ''
#THEN rsync that dir structure across.
    my ($pathdir, $delete) = @_;


    #CAUTION: strange behaviour with getpwent . calling 2nd time gives nothing. 
    my %uid; #uid VALUE based on uname key
    while (my @ent = getpwent() ){
        $uid{$ent[0]} = $ent[2];
    }
    #THIS LINE very important, else NEXT call to getpwent() returns zero records!!!
    endpwent();

    # while ( my ($k,$v) = each %uid  ){
        # say " UID key: $k = $v ";
    # }

    while ( my ($key,$value) = each %fileSourceMap) {
        my @arr = @{$value};
     
        my $l = $arr[0];
        my $t = $arr[1];
        my $u = $arr[2];
        my $g = $arr[3];
        my $m = $arr[4];

        printf "COPYING >>> key:%s, level:%d, type:%s user:%s group:%s  mode:%s \n"
            ,$key
            ,$l // 'NULL'
            ,$t // 'NULL'
            ,$u // 'NULL'
            ,$g // 'NULL'
            ,$m // 'NULL';

        my $sourcefile = $sourcedir . $key; 
        my @file = ( $sourcefile );        
        #CAUTION!!! chmod NEEDS OCTAL value! not string, or decimal!!!
        # printf "modeOCT 777 = %o \n" , oct('777') ;
        # printf "modeOCT 0777 = %o \n", oct('0777') ;
        # printf "modeOCT 00777 = %o \n", oct('00777') ;
        
        chmod( oct($m), @file) == @file || die "chmod failed: @file : $!";
        my $gid = (getgrnam($g))[2];
        my $this_uid = $uid{$u};
        chown($this_uid, $gid, @file) == @file || die "chown failed: @file: $!";
    }
    my $logfilepart = $pathdir;     
    $logfilepart =~ s/\//\_/g; #replace / with _ char. 
    my $rsync_switches=" $dryrun -a --human-readable --verbose  ";
    my $rsync_backup=" --backup --backup-dir=${backupdir}${pathdir} " ;
    my $rsync_logfile=" --log-file=$logfiledir/${logfilepart}_" . time() . ".log ";
    my $rsync_delete = $delete ? " --delete " : "";
    
    #prefix normally /home/foo/Downloads/perl_test to safeguard against overcopy.
    my $targetdir = $TEST_PREFIX . $pathdir;
    
    #CAUTION: OpenBSD does not do -v for mkdir 
    my $mkdir_target = "mkdir -p $targetdir";
    my $res = qx/$mkdir_target/;
    say "result mkdir target: " . $res;
    
    #IMPORTANT! use the trailing  '/' at end of rsync source to avoid starting at the dir, ..so to get contents of the dir.
    #TODO: Rust's version FAILES when extra blank space chars are between args. Dbl check here. 
    # ...rsync main.c (1492) err or something. 
    my $rsync = "rsync $rsync_switches $rsync_delete $rsync_backup $rsync_logfile ${sourcedir}${pathdir}/ $targetdir ";
    say $rsync; 
    $res = qx/$rsync/;
    say "rsync : $res";

}


sub scanSource{
#create hashtable for the filesystem structure to then do a acl/mode comparision against .
    my ($pathdir) = @_;
   
    scanSourceDir($pathdir, 0);
    showPrelim(0);
}

sub getParentPerms{
#this filepath does NOT exist in the XML Treepath, so do up a level and get the default values. 
    my ($keypath) = @_; 
    # say "keypath: $keypath";
    my @dirs =  split '/', $keypath; 
    my $lastdirpos = rindex $keypath, '/';
    my $lastdir = substr($keypath,0, $lastdirpos ) ;
    # say "lastdir: $lastdir";  
    my $v = $fileMap{$lastdir};
    if (! defined $v) {
        say "ERROR: there is no key in the XML spec tree for '$lastdir '";
        say "Adjust XML spec or similar";
        die();
    } 
    my @arr = @{$v};

    return ( $arr[5] , $arr[6],  $arr[7], $lastdir );
}

sub showPrelim{
#show to user What will happen re file Mode, Missing etc   
#iterate the xmltree first then the filesys source tree 
    my ($reshow) = @_;

    say "XML Tree spec map: ";
    say "??? = File missing from XML spec master file.";
    while ( my ($key,$value) = each %fileMap) {
        my @arr = @{$value};
        my $tag = '   ';
        if ( !exists $fileSourceMap{$key}){
            $tag = '???'
        }

        printf "%s File: (lv %d)(%s) %s %s:%s  %s\n"
            ,$tag
            ,$arr[0]
            ,($arr[1] // '?') =~ tr/fd/FD/r   
            ,$key 
            ,$arr[2] // 'NULL'
            ,$arr[3] // 'NULL'
            ,$arr[4] // 'NULL';
    }

    say "Filesystem source map...";
    say "??? = File not mentioned in XML Tree spec. ";
    say "XXX = File's mode will be overridden to match the XML file spec. ";
    while ( my ($key,$value) = each %fileSourceMap) {
        my @arr = @{$value};
        my $msg = ''; 
        my $tag = '   ';
        if ( exists $fileMap{$key} ) {
             #it exists in the XML treemap...
             #0=level,1=type, 2=user, 3=group, 4=mode
             #the fileSourceMap CANNOT really have the target user/group as it is coming from a dev machine anyway. 
             $fileSourceMap{$key}[2] = $fileMap{$key}[2];
             $fileSourceMap{$key}[3] = $fileMap{$key}[3];

            if ($fileMap{$key}[4] ne $arr[4] ){
                $tag="XXX";
                $msg="**Override** $arr[4] --> $fileMap{$key}[4] ";
                #RESET value to match the XML spec.
                $fileSourceMap{$key}[4] = $fileMap{$key}[4];
            }
        }else {
            #missing file
            #get last dir / go up a dir and get the default perms for that file. 
            my @perms = getParentPerms($key); 
            $tag="???";
            $msg="**Missing** (owner dir: $perms[3])";
            $fileSourceMap{$key}[2] = $perms[0];
            $fileSourceMap{$key}[3] = $perms[1];
            $fileSourceMap{$key}[4] = $perms[2];
        }

        say "$tag File: (lv $arr[0])(" . $arr[1] =~ tr/fd/FD/r . ") $key ${arr[2]}:${arr[3]} $arr[4] $msg "; 
    }

    say "tree spec count ", %fileMap + 0; 
    say "file source count ", %fileSourceMap + 0 ;

    if ($forceYes eq 'yes' ){
        say "FORCING a Yes for all would-be user input!";
    }else {
        say "Considering all above, proceed with the file copy tasks? y/N";
        if ( defined($_ = <STDIN>)) {
            chomp;
            my $ans = $_; 
            #say "ans='$ans' ";
            if ($ans eq '' || $ans eq 'y' ) {
                if ($reshow != 1){
                    showPrelim(1);
                }
                say "Proceeding...";
            }elsif ($ans eq 'N' ){
                say "Ending now.";
                die();
            }else {
                say "Couldn't understand response. Terminating now. ";
                die();

            }
        }
    }
}


sub getMode{
#do a file stat to get the Mode. 
#the perl chmod NEEDS an octal value input! 
#fyi: at THIS stage, it seems the result is bitmasked and output for the decimal output etc 
#but please note the octal printout format AND the bitwise mask 
    my ($uri) = @_; 
    my $file_mode = (stat($uri))[2];
    return sprintf "%04o", $file_mode & 07777;
}

sub scanSourceDir{
#recusive scan into filesystem sourcedir to create hashmap of filesdirs
#to crossref with xml trees version 
    my ($curdir , $level) = @_;
    my $fulldir = $sourcedir . $curdir;

    $fileSourceMap{$curdir} = [ fileData($level, 'd', 'NULL', 'NULL', getMode($fulldir)) ]; 
    #[$level, $curdir, getMode($fulldir) ];

    opendir my ($dirh) , $fulldir; 
    while (readdir $dirh) {
        next if $_ eq ".";
        next if $_ eq "..";
        my $fullname=$fulldir.'/'.$_;

        if ( -f $fullname ) {
            $fileSourceMap{$curdir.'/'.$_ } = [ fileData($level, 'f', 'NULL', 'NULL', getMode($fullname)) ];
            #discard soon, array indexes need to be the same!
            #[ $level, $_ , getMode($fullname) ];
        }  

        if ( -d $fullname ) {
            scanSourceDir($curdir.'/'.$_ , $level+1);
        }  
    }
    closedir $dirh;
}


