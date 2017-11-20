#!/usr/bin/perl -w

use strict;
use warnings;

use Time::HiRes qw/ time sleep /; #Used to get how long verify may run
use POSIX;

my($sdX, $totsect, $osect, $TotSampleAmt, $NumOfSamples, $sections, $offset, $obs, $rndrange, $skip, $i, $j, $k);
my($bs, $predata, @predata, $anythg, $readloc, $bogus, $samplefile, $drvsize, $smpsize, $readtime, @words, $wcnt);
my($lcnt, $loc, $logfile, @logdata, $lrecord, $product, $vendor, $serial, $verstart, $verend, $dskflg, $tsdX);

sub init
{
 system("clear");
 if (@ARGV < 1) # Didn't enter a device
 {
  print("\n**** Missing device to verify: sda or sdb or sdX\nCurrent devices available...\n\n");
  system("fdisk -l");
  exit;
 }
 else
 {
  $sdX=$ARGV[0];                 # disk to be verified
 }
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
 $loc="JW";
 $logfile="/usr/local/bin/DeviceWipeVerify.log";
 $samplefile="/tmp/sanchk.tmp"; # Location of sample to scan
 $TotSampleAmt=0.1;             # % of disk to be sampled (10%)
 $sections=1024;                # disk divided in sections for even random sampling
 $NumOfSamples=2;               # NUMBER OF RANDOM SAMPLES PER $sections
 open (FH, "< words.dic") or die "Can't open words.dic for read: $!"; #10k common USA words > 4 chars to scan drives
 @words = <FH>;
 close FH or die "Cannot close words.dic: $!";
}

sub wdrv # Which device to check
{
 @predata=split(/,/,$predata);
 $predata=$predata[2];
 @predata=split(/ /,$predata);
 $totsect=$predata[1]; # total number of sectors
 $predata=`fdisk -l /dev/$sdX | grep -i unit`;
 @predata=split(/=/,$predata);
 $predata=$predata[1];
 @predata=split(/ /,$predata);
 $bs=$predata[1]; # Disk sector size in bytes (standard is 512 bytes)
 $drvsize=$totsect*$bs/1024/1024/1024;
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
 printf("Disk size: %.1fgb, Verification size: %.1fgb, Estimated runtime: %.2f min\n",$drvsize, $smpsize, $readtime);
}

sub chkdrv # Start checking the device - copy the sample ($samplefile) to the tmp dir and scan
{
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
 $bogus=localtime;
 print("Verification started @ $bogus\n\n");
 $verstart=strftime("%Y-%m-%d %H:%M:%S",localtime(time));
 for($i=0;$i<$sections;++$i)
 {
#  $samplefile="/tmp/sanchk-$i.tmp"; # Location of sample to scan
  if($i==0) #(READ MBR)
  {
   $skip=0; # Used to move to each section for sampling
   $readloc=$skip;
   system("dd if=/dev/$sdX of=$samplefile skip=$skip count=1 bs=$obs 1>/dev/null 2>&1");
   chksmpl();
  }
  for($j=0;$j<$NumOfSamples;++$j)
  {
   $readloc=int(rand($rndrange));
   $readloc=$skip+$readloc;
   $readloc=($readloc>$osect-1)?($osect-1):$readloc;
   system("dd if=/dev/$sdX of=$samplefile skip=$readloc count=1 bs=$obs 1>/dev/null 2>&1");
   chksmpl();
  }
  $skip=$skip+$offset;
  printf("\rDisk verified: %.0f%%",($i/$sections)*100);
 }
 $skip=$totsect-512;
 system("dd if=/dev/$sdX of=$samplefile skip=$skip count=512 bs=$bs 1>/dev/null 2>&1");
 chksmpl();
 print("\rDisk verified: 100%\n\n");
 $verend=strftime("%Y-%m-%d %H:%M:%S",localtime(time));
 $bogus=localtime;
 print("Verification ended @   $bogus\n");
 verlog();
}

sub chksmpl # Review the sample for data
{
 $anythg=`strings $samplefile`;
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
   print("\n\n!!!!! Data found on disk!!!!\nSection: $i\nDisk location: = $readloc\n\nSample contents:\n$bogus\n\n!!!! Re-run sanitization!!!!\n\n");
   exit;
  }
 }
}

sub verlog
{
 #Location|Product|Vendor|SerialNum|SanType|SanMethod|StartWipe|EndWipe|TotDrvSize|TotSampleSize|NumofSamples|StartVerf|EndVerf
 $lrecord=sprintf("%s|%s|%s|%s|Unknown|Unknown||", $loc, $product, $vendor, $serial);
 $lrecord.=sprintf("|%.1fgb|%.1fgb|%d|%s|%s\n",$drvsize, $smpsize, $NumOfSamples*$sections, $verstart, $verend);
 open (FH, ">> $logfile") or die "Can't open $logfile for write: $!";
 print FH $lrecord;
 close FH or die "Cannot close $logfile: $!";
}


&init();
&wdrv();
&chkdrv();
