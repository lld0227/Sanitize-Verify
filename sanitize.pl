#!/usr/bin/perl -w

use strict;
use warnings;

use Time::HiRes qw/ time sleep /; #Used to get how long verify may run
use POSIX;

my($sdX, $totsect, $devchk, $i, $j, $k, $count, $wipe, $sanflg, $sections, $skip, $loc, $secer);
my($bs, $obs, $predata, @predata, $bogus, $drvsize, $wipetime, $readloc, $samplefile, $readtime);
my($bufcnt, $osect, $NumOfSamples, $rndrange, $offset, $anythg, $wcnt, @words, $TotSampleAmt, $smpsize);
my($logfile, $lrecord, @logdata, $lcnt, $dskflg, $tsdX, $vfyfail, $sum, @sum, $bwt, $bbs, $leftsect);
my($product, $vendor, $serial, $wipemeth, $wipestart, $wipeend, $verstart, $verend);

sub init
{
 system("clear");
 if (@ARGV < 1) # Didn't enter a device
 {
  print("\n**** Missing device to Sanitize: sda, sdb, sd(n)...\nCurrent devices available...\n\n");
  system("fdisk -l");
  exit;
 }
 $sdX=$ARGV[0];                 # disk to be verified
 if($sdX =~ /\//)
 {
  @predata=split(/\//,$sdX);
  $bogus = @predata;
  $sdX = $predata[$bogus-1];
 }
 $predata=`fdisk -l | grep $sdX | grep sectors\$`;
 if(length($predata) < 1 || length($sdX)<3 || $sdX eq 'dev')
 {
  print("\n**** Can not find device: $sdX\nCurrent devices available...\n\n");
  system("fdisk -l");
  exit;
 }
 $tsdX="";
 $loc="JW";
 $leftsect=0;
 $samplefile="/tmp/sanchk.tmp"; # Location of sample to scan
 $logfile="/usr/local/bin/DeviceWipeVerify.log";
 $TotSampleAmt=0.1;             # % of disk to be sampled (10%)
 $sections=1024;                # disk divided in sections for even random sampling
 $NumOfSamples=2;               # NUMBER OF RANDOM SAMPLES PER $sections
 open (FH, "< /usr/local/bin/words.dic") or die "Can't open words.dic for read: $!"; #10k common USA words > 4 chars to scan drives
# open (FH, "< words.dic") or die "Can't open words.dic for read: $!"; #10k common USA words > 4 chars to scan drives
 @words = <FH>;
 close FH or die "Cannot close words.dic: $!";
}

sub seldev
{
 $predata=`fdisk -l | grep $sdX | grep sectors\$`;
 @predata=split(/,/,$predata);
 $predata=$predata[2];
 @predata=split(/ /,$predata);
 $totsect=$predata[1]; # total number of sectors
 $predata=`fdisk -l /dev/$sdX | grep -i ^unit`;
 @predata=split(/=/,$predata);
 $predata=$predata[1];
 @predata=split(/ /,$predata);
 $bs=$predata[1]; # Disk sector size in bytes (standard is 512 bytes)
 $drvsize=$totsect*$bs/1024/1024/1024;
 $bogus=`mount |grep $sdX | grep ' / '`;
 system("fdisk -l");
 print("\n");
 print("******************************************************************************************\n");
 printf(" You have choosen device: >>>> /dev/%s <<<< Disk size: %.1fgb for sanitization\n\n", $sdX, $drvsize);
 if(length($bogus)>0)
 {
  print(" FYI - You booted off of this drive...\n\n");
 }
 print(" ARE YOU SURE??\n");
 print("******************************************************************************************\n\n");
 print(" Type y <Enter> to continue, anything else to cancel ");
 $wipe=<STDIN>;
 chomp($wipe);
 exit 0 if( !(uc($wipe) eq 'Y'));
}

sub probdev
{
 $predata=`hdparm -I /dev/$sdX 2>&1 | grep -i ^security`;
   if(length($predata) < 1){$secer=0;}
 else                      {$secer=1;}
}

sub selwipe
{
 if($secer)
 {
  print("\n\n\n Device to be sanitized: /dev/$sdX\n\n Sanitization methods: Embedded ATA/SATA Secure Erase (preferred)\n                       The 3 pass overwrite\n\n");
  print(" Hit <Enter> to perform Secure Erase or 3 <Enter> for 3 pass overwrite: ");
  $wipe=<STDIN>;
  chomp($wipe);
    if( $wipe eq 3){$sanflg=1;}
  else             {$sanflg=2;}
 }
 else
 {
  print("\n Device: /dev/$sdX can not use the embedded ATA/SATA Secure Erase\n That means only option is 3 pass overwrite\n");
  $sanflg=1;
 }
 if($sanflg==2)
 {
  $predata=`hdparm -I /dev/$sdX 2>&1 | grep -i frozen`;
  if($predata !~ /not/i && !(-e "/tmp/sleep"))
  {
   print(" Got to put the system in sleep mode for a sec, hit the power button to continue\n");
   sleep 3;
   system("touch /tmp/sleep");
   system("echo -n mem > /sys/power/state");
  }
  if(-e "/tmp/sleep"){system("rm /tmp/sleep");}
  $predata=`hdparm -I /dev/$sdX 2>&1 | grep -i frozen`;
  if($predata !~ /not/i ) {print("Still not working...");exit;}
 }
 wipe();
}

sub bestwt
{
 $bwt=$bbs=100000000;
 print("\n Calculating fastest write time...\n");
 for($i=10;$i<19;++$i)
 {
  $obs=(2**$i);
  system("dd if=/dev/$sdX of=/dev/$sdX count=16  skip=200  bs=$obs 1> /tmp/ddtime.txt 2>&1");
  system("dd if=/dev/$sdX of=/dev/$sdX count=128 skip=200  bs=$obs 1>>/tmp/ddtime.txt 2>&1");
  system("dd if=/dev/$sdX of=/dev/$sdX count=16  skip=2000 bs=$obs 1>>/tmp/ddtime.txt 2>&1");
  system("dd if=/dev/$sdX of=/dev/$sdX count=128 skip=2000 bs=$obs 1>>/tmp/ddtime.txt 2>&1");
  @predata = `grep \/s /tmp/ddtime.txt`;
  $lcnt = @predata;
  $sum=0;
  for($k=0;$k<$lcnt;++$k)
  {
   @sum=split(',',$predata[$k]);
   if($sum[3] =~ /kb/i){@logdata=split(' ',$sum[3]);$sum=$sum+$logdata[0]/1000;}
   if($sum[3] =~ /mb/i){@logdata=split(' ',$sum[3]);$sum=$sum+$logdata[0];}
   if($sum[3] =~ /gb/i){@logdata=split(' ',$sum[3]);$sum=$sum+$logdata[0]*1000;}
  }
  $sum=$sum/$lcnt;
  $wipetime=$drvsize*1024/$sum/60;
  if($bwt>$wipetime){$bwt=$wipetime;$bbs=$obs;}
 }
 $obs=$bbs;
 $count=int($totsect/($bbs/$bs));
 $leftsect=$totsect-$count*($bbs/$bs);
 printf(" Estimated Sanitization Time: %.2f min\n",$bwt);
}



sub wipe
{
 $vfyfail=0;
 system("lshw -c disk > /tmp/logdata.txt 2>/dev/null");
 open (FH, "< /tmp/logdata.txt") or die "Can't open logdata.txt for read: $!";
 @logdata = <FH>;
 close FH or die "Cannot close logdata.txt: $!";
 $lcnt = @logdata;
 for($k=0;$k<$lcnt;++$k)
 {
  if($logdata[$k] =~ /\*-disk/i || $dskflg)
  {
   $dskflg=1;
      if($logdata[$k] =~ /product/i){@predata=split(/:/,$logdata[$k]);$product=$predata[1];$product=~s/[\000-\037]//g;$product=~s/^\s+|\s+$//g;}
   elsif($logdata[$k] =~ /vendor/i){@predata=split(/:/,$logdata[$k]);$vendor=$predata[1];$vendor=~s/[\000-\037]//g;$vendor=~s/^\s+|\s+$//g;}
   elsif($logdata[$k] =~ /logical name/i){@predata=split(/:/,$logdata[$k]);$tsdX=$predata[1];$tsdX=~s/[\000-\037]//g;$tsdX=~s/^\s+|\s+$//g;}
   elsif($logdata[$k] =~ /serial/i){@predata=split(/:/,$logdata[$k]);$serial=$predata[1];$serial=~s/[\000-\037]//g;$serial=~s/^\s+|\s+$//g;}
   elsif($logdata[$k] =~ /configuration/i){$dskflg=0;if($tsdX =~ $sdX){last;}else{$product=$vendor=$serial="";}}
  }
 }
 if($sanflg==1)
 {
  bestwt();
  $wipestart=strftime("%Y-%m-%d %H:%M:%S",localtime(time));
  $wipemeth="3pass";
  $bogus=localtime();
  print(" Starting First Pass... @ $bogus\n");
  system("dd if=/dev/urandom of=/dev/$sdX count=$count bs=$obs 1>/dev/null 2>&1");
  if($leftsect){ system("dd if=/dev/urandom of=/dev/$sdX count=$leftsect bs=$bs 1>/dev/null 2>&1");}
  $bogus=localtime();
  print(" Starting Second Pass...@ $bogus\n");
  system("dd if=/dev/urandom of=/dev/$sdX count=$count bs=$obs 1>/dev/null 2>&1");
  if($leftsect){ system("dd if=/dev/urandom of=/dev/$sdX count=$leftsect bs=$bs 1>/dev/null 2>&1");}
  $bogus=localtime();
  print(" Starting Last Pass...  @ $bogus\n");
  system("dd if=/dev/zero of=/dev/$sdX count=$count bs=$obs 1>/dev/null 2>&1");
  if($leftsect){ system("dd if=/dev/zero of=/dev/$sdX count=$leftsect bs=$bs 1>/dev/null 2>&1");}
  $wipeend=strftime("%Y-%m-%d %H:%M:%S",localtime(time));
  $bogus=localtime();
  print(" Finished               @ $bogus\n");
 }
 else
 {
  $predata=`hdparm -I /dev/$sdX 2>&1 | grep ERASE`;
  @predata=split(/ /,$predata);
  $bogus=$predata[0]; # total number of sectors
  $bogus =~ s/^\s+|\s+$//g;
  print("\n This process will be using Secure Erase. Once started it must complete or device will be inoperable...\n");
  print("\n It is estimated to complete in $bogus...\n");
  print(" Enter y to continue, anything else to cancel ");
  $wipe=<STDIN>;
  chomp($wipe);
  exit 0 if( !(uc($wipe) eq 'Y'));
  $wipestart=strftime("%Y-%m-%d %H:%M:%S",localtime(time));
  $wipemeth="SecErase";
  $bogus=localtime();
  print(" Starting Secure Erase...@ $bogus\n");
  system("hdparm --user-master u --security-set-pass Eins /dev/$sdX 1>/dev/null 2>&1");
  system("hdparm --user-master u --security-erase Eins /dev/$sdX 1>/dev/null 2>&1");
  $wipeend=strftime("%Y-%m-%d %H:%M:%S",localtime(time));
  $bogus=localtime();
  print(" Finished                @ $bogus\n");
 }
 verify();
}

sub verify
{
 print("\n\n Starting Verification Process\n");
 $smpsize=$drvsize*$TotSampleAmt;
 $obs=int($totsect*$TotSampleAmt/($sections*$NumOfSamples));
 $obs=2**(int(log($obs)/log(2))+1); #(Read number of block size $bs to match $TotSampleAmt% of disk) (TRUNCATE REMAINDER)
 $osect=int($totsect*$bs/$obs);
 $offset=int($osect/$sections);
 $rndrange=($offset-1); #(Value used with random to read in current section)
 $readtime=time;
 system("dd if=/dev/$sdX of=$samplefile skip=100 count=1 bs=$obs 1>/dev/null 2>&1");
 $anythg=`strings /tmp/sanchk.tmp`;
 $readtime=time-$readtime;
 $readtime=($readtime*$NumOfSamples*$sections)/60;
 printf(" Disk size: %.1fgb, Verification size: %.1fgb, Estimated runtime: %.2f min\n",$drvsize, $smpsize, $readtime);
 $verstart=strftime("%Y-%m-%d %H:%M:%S",localtime(time));
 $bogus=localtime();
 print(" Verification started @ $bogus\n\n");
 for($i=0;$i<$sections;++$i)
 {
  if($i==0) #(READ MBR)
  {
   $skip=0; # Used to move to each section for sampling
   $readloc=$skip;
   system("dd if=/dev/$sdX of=$samplefile skip=$skip count=1 bs=$obs 1>/dev/null 2>&1");
   chksmpl();
   $readloc=int(rand($rndrange));
   $readloc=$skip+$readloc;
   $readloc=($readloc>$totsect-$bufcnt)?($totsect-$bufcnt):$readloc;
   system("dd if=/dev/$sdX of=$samplefile skip=$readloc count=1 bs=$obs 1>/dev/null 2>&1");
   chksmpl();
  }
  else
  {
   for($j=0;$j<$NumOfSamples;++$j)
   {
    $readloc=int(rand($rndrange));
    $readloc=$skip+$readloc;
    $readloc=($readloc>$osect-1)?($osect-1):$readloc;
    system("dd if=/dev/$sdX of=$samplefile skip=$readloc count=1 bs=$obs 1>/dev/null 2>&1");
    chksmpl();
   }
  }
  $skip=$skip+$offset;
  if(!($i%10)){$bogus=$i/10;print("\rDisk verified: $bogus%")};
  if($vfyfail){last;}
 }
 if($vfyfail){wipe();}
 else
 {
  $skip=$totsect-512;
  system("dd if=/dev/$sdX of=$samplefile skip=$skip count=512 bs=$bs 1>/dev/null 2>&1");
  chksmpl();
 }
 if($vfyfail){wipe();}
 else
 {
  print("\rDisk verified: 100%\n\n");
  $verend=strftime("%Y-%m-%d %H:%M:%S",localtime(time));
  $bogus=localtime;
  print("Verification ended @   $bogus\n");
  verlog();
 }
}

sub chksmpl # Review the sample for data
{
 $anythg=`strings /tmp/sanchk.tmp`;
 if(length($anythg)>0) #any strings > 4 chars found, check for words
 {
  $bogus="";
  $wcnt = @words;
  for($k=0;$k<$wcnt;++$k)
  {
   next if $anythg !~ /$words[$k]/i;
   $bogus = $words[$k];
   last;
  }
  if(length($bogus)>0) # Any words found, stops the scan and states to re-run sanitization
  {
   system("clear");
   print("!!!!! Data found on disk!!!!\nSection: $i\nDisk location: = $readloc\n\nSample contents:\n$bogus\n\n!!!! Re-running sanitization!!!!\n\n");
   $vfyfail=1;
   if($sanflg==2){$sanflg=1}
   else
   {
    print("\n\n Strange, the 3 pass overwrite was just used and there is still data, that's not suppose to happen!!\n");
    exit -1;
   }
  }
 }
}

sub verlog
{
 #Location|Product|Vendor|SerialNum|SanType|SanMethod|StartWipe|EndWipe|TotDrvSize|TotSampleSize|NumofSamples|StartVerf|EndVerf
 $lrecord=sprintf("%s|%s|%s|%s|purge|%s|%s|%s", $loc, $product, $vendor, $serial, $wipemeth, $wipestart, $wipeend);
 $lrecord.=sprintf("|%.1fgb|%.1fgb|%d|%s|%s\n",$drvsize, $smpsize, $NumOfSamples*$sections, $verstart, $verend);
 open (FH, ">> $logfile") or die "Can't open $logfile for write: $!";
 print FH $lrecord;
 close FH or die "Cannot close $logfile: $!";
}

&init();
&seldev();
&probdev();
&selwipe();
