
package main;

use strict;
use warnings;

use HiPi::Device::SPI;
use HiPi::Device::SPI qw( :spi );
use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
use Error qw(:try);
use Sys::Hostname;
use Socket;	# für die IP-Adresse
use IO::Socket::INET;


use constant {
	DOGM204_REG_CMD			=> 0,	# Command Bytes
	DOGM204_REG_DATA		=> 1,	# Data Bytes

	DOGM204_CMD_CLEAR		=> 0x01,
	DOGM204_CMD_SET_POS		=> 0x80,
	DOGM204_CMD_DISPLAY_ON	=> (0x08 | 0x04),
	DOGM204_CMD_CURSOR_ON	=> (0x08 | 0x02),
	DOGM204_CMD_BLINK_ON	=> (0x08 | 0x01),
};

my %sets = (
	'clear' => "",
	'line' => "",
	'pos' => "",
	'output' => "",
);

##################################################
# Forward declarations
#
sub SPI_DOGM204_Initialize($);
sub SPI_DOGM204_Define($$);
sub SPI_DOGM204_Attr(@);
sub SPI_DOGM204_Poll($);
sub SPI_DOGM204_Set($@);
sub SPI_DOGM204_Get($);
sub SPI_DOGM204_Undef($$);
sub SPI_DOGM204_WriteByte($$$);
sub SPI_DOGM204_ReadByte($$);
sub SPI_DOGM204_WaitBusy($$);
sub SPI_DOGM204_InitController($);
sub SPI_DOGM204_Clear($);
sub SPI_DOGM204_SetPos($$);
sub SPI_DOGM204_Output($$);

# This idea was stolen from Net::Address::IP::Local::connected_to()
sub get_local_ip_address {
    my $socket = IO::Socket::INET->new(
        Proto       => 'udp',
        PeerAddr    => '198.41.0.4', # a.root-servers.net
        PeerPort    => '53', # DNS
    );

    # A side-effect of making a socket connection is that our IP address
    # is available from the 'sockhost' method
    my $local_ip_address = $socket->sockhost;

    return $local_ip_address;
}

sub SPI_CBerry28_Demo($$) {
	my ($hash, $dev) = @_;
	my $name = $hash->{NAME};

	print "SPI_CBerry28_Demo: start\n";

	# check for existing spi device
	my $spiModulesLoaded = 0;
	$spiModulesLoaded = 1 if -e $dev;

	if ($spiModulesLoaded) {
		if (-r $dev && -w $dev) {
			$hash->{spiDev} = HiPi::Device::SPI->new(
				devicename	=> $dev,
				speed		=> SPI_SPEED_KHZ_500,
			#	busmode		=> SPI_MODE_3,
				bitsperword	=> 8,
				delay		=> 0,
			);
			print "SPI_CBerry28_Demo device created\n";

			# default values
			$hash->{lines} = 4;
			$hash->{chars} = 20;
			$hash->{cpl} = 32;
			$hash->{pos} = 0;
			$hash->{timeout} = 200000;
			$hash->{failed} = 0;

			# Initialize Display
			SPI_DOGM204_InitController($hash);
			# Clear Display
			SPI_DOGM204_Clear($hash);

			my $host = hostname();
			my $address = get_local_ip_address();	#inet_ntoa(scalar gethostbyname( $host || 'localhost' ));
			
			my @curtime = localtime;

			# print a nice representation
			my $text = sprintf("%d-%02d-%02d %02d:%02d",
				$curtime[5] + 1900, $curtime[4] + 1, $curtime[3], $curtime[2], $curtime[1]);
			
			# Welcome Message
			SPI_DOGM204_SetPos($hash, 0 * $hash->{chars});
			SPI_DOGM204_Output($hash, 'IP = ' . $address);
			SPI_DOGM204_SetPos($hash, 1 * $hash->{chars});
			SPI_DOGM204_Output($hash, 'Host = ' . $host);
			SPI_DOGM204_SetPos($hash, 2 * $hash->{chars});
			SPI_DOGM204_Output($hash, $text);

			SPI_DOGM204_Undef($hash, 0);
			
		} else {
			my @groups = split '\s', $(;
			print "$name :Error! $dev isn't readable/writable by user " . getpwuid( $< ) . " or group(s) " .
				getgrgid($_) . " " foreach(@groups);
		}

	} else {
		my $devices = HiPi::Device::SPI->get_device_list();
		print "$name : Error! SPI device not found: $dev . Please check that these kernelmodules are loaded: spi_bcm2708, spidev $devices";
	}
	print "SPI_CBerry28_Demo: end\n";

	return undef;
}

sub SPI_DOGM204_Undef($$) {
	my ($hash, $arg) = @_;

	$hash->{spiDev}->close( ).
	return undef;
}

sub SPI_DOGM204_WriteByte($$$) {
	my ($hash, $register, $value) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	if ($hash->{failed} != 0) {
		return $retVal;
	}
	
#	print "SPI_DOGM204_WriteByte: start\n";
	
	eval {
		# 5 synchronization bits, read bit = 0
		my @temp = (0xF8, 0x00, 0x00);
		# register select
		if ($register == DOGM204_REG_DATA) {
			$temp[0] |= 0x02;
		}
		# lower data bits, lsb first
		$temp[1]  = ($value & 0x01) << 7;
		$temp[1] |= ($value & 0x02) << 5;
		$temp[1] |= ($value & 0x04) << 3;
		$temp[1] |= ($value & 0x08) << 1;
		# upper data bits, lsb first
		$temp[2]  = ($value & 0x10) << 3;
		$temp[2] |= ($value & 0x20) << 1;
		$temp[2] |= ($value & 0x40) >> 1;
		$temp[2] |= ($value & 0x80) >> 3;
		# debug
		print "SPI_DOGM204_WriteByte: OUT $value -> $temp[0] $temp[1] $temp[2] \n";
		# transfer
		my @resp = unpack ('C3', $hash->{spiDev}->transfer( pack('C3', @temp) ));
		# debug
	#	print "SPI_DOGM204_WriteByte: IN  " . length(scalar @resp) . "B: $resp[0] $resp[1] $resp[2] \n";
		print "SPI_DOGM204_WriteByte: IN  $resp[0] $resp[1] $resp[2] \n";
		
		$retVal = $resp[0];
		
		print "SPI_DOGM204_WriteByte: $retVal \n";

	} or do {
		my $e = $@;
		print "ERROR: SPI_DOGM204_WriteByte: ( $register , $value ) exception ( $e )\n";
		$hash->{failed} = 1;
		$retVal = 0;
	};

	return $retVal;
}

sub SPI_DOGM204_ReadByte($$) {
	my ($hash, $register) = @_;
	my $name = $hash->{NAME};

	my $retVal = 0;

	if ($hash->{failed} != 0) {
		return $retVal;
	}
	
#	print "SPI_DOGM204_ReadByte: start\n";
	
	eval {
		# 5 synchronization bits, read bit = 1
		my @temp = (0xF8 | 0x04, 0x00, 0x00);
		# register select
		if ($register == DOGM204_REG_DATA) {
			$temp[0] |= 0x02;
		}
		# debug
		print "SPI_DOGM204_ReadByte: OUT $temp[0] $temp[1] $temp[2] \n";
		# transfer
		my @resp = unpack ('C3', $hash->{spiDev}->transfer( pack('C3', @temp) ));

		# debug
	#	print "SPI_DOGM204_ReadByte: IN  " . length(scalar @resp) . "B: $resp[0] $resp[1] $resp[2] \n";
		print "SPI_DOGM204_ReadByte: IN  $resp[0] $resp[1] $resp[2] \n";

		$retVal = $resp[2];
		
		print "SPI_DOGM204_ReadByte: $retVal \n";
	} or do {
		my $e = $@;
		print "ERROR: SPI_DOGM204_ReadByte: exception ( $e )\n";
		$hash->{failed} = 1;
		$retVal = 0;
	};

	return $retVal;
}

sub SPI_DOGM204_WaitBusy($$) {
	my ($hash, $delay) = @_;
	my $name = $hash->{NAME};

	my $retVal = 0;
	my $timeout = $hash->{timeout};

	if ($hash->{failed} != 0) {
		return $retVal;
	}
	
	print "SPI_DOGM204_WaitBusy: $delay \n";

	while ($retVal == 0 && $timeout > 0) {
		# read data
		my $resp = SPI_DOGM204_ReadByte($hash, 0);
		# test flag
		#if ((resp[2] & 0x1) == 0)
		if (($resp & 1) == 0) {
			$retVal = 1;
		} else {
			# wait
			usleep($delay);
		}
		$timeout -= $delay;
	}

	return $retVal;
}

sub SPI_DOGM204_InitController($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	if ($hash->{failed} != 0) {
		return $retVal;
	}
	
	print "SPI_DOGM204_InitController:\n";

	eval {
		# function set: 8 bit data length, RE=1, REV=0
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x3A);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# ext. function set: 5 dot font, 4 line display
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x09);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# entry mode set: bottom view
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x06);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# bias setting
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x1E);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# function set: 8 bit data length, RE=0, IS=1
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x39);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# internal osc
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x1B);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# divider on, set value
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x6E);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# booster on, set contrast
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x57);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# set contrast
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x72);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# function set: 8 bit data length, RE=0, IS=0
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x38);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# display on, cursor on, blink on;
		#SPI_DOGM204_WriteByte($hash, 0, 0x0F);
		# display on
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, 0x08 | 0x04);
		SPI_DOGM204_WaitBusy($hash, 10000);

		$retVal = 1;

		print "SPI_DOGM204_InitController: $retVal\n";
	} or do {
		my $e = $@;
		print "ERROR: SPI_DOGM204_InitController: exception ( $e )\n";
		$hash->{failed} = 1;
	};

	return $retVal;
}

sub SPI_DOGM204_Clear($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	if ($hash->{failed} != 0) {
		return $retVal;
	}

	print "SPI_DOGM204_Clear:\n";

	eval {
		# clear display
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, DOGM204_CMD_CLEAR);
		# wait
		SPI_DOGM204_WaitBusy($hash, 2000);

		$retVal = 1;

	} or do {
		my $e = $@;
		print "ERROR: SPI_DOGM204_Clear: exception ( $e )\n";
	};

	return $retVal;
}

sub SPI_DOGM204_SetPos($$) {
	my ($hash, $pos) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;
	my $line = 0;

	# update internals first
	if ($pos >= 0 and $pos < ($hash->{lines} * $hash->{chars})) {
		$line = $pos / $hash->{chars};
		$pos = $pos % $hash->{chars};
		$hash->{pos} = $line * $hash->{cpl} + $pos;
		
	} else {
		return $retVal;
	}
	
	if ($hash->{failed} != 0) {
		return $retVal;
	}

	eval {
		# set DDRAM address
		print "SPI_DOGM204_SetPos: $line / $pos \n";
		
		SPI_DOGM204_WriteByte($hash, DOGM204_REG_CMD, DOGM204_CMD_SET_POS + $hash->{pos});
		usleep(100);
		
		$retVal = 1;

	} or do {
		my $e = $@;
		print "ERROR: SPI_DOGM204_SetPos: exception ( $e )\n";
	};

	return $retVal;
}

sub SPI_DOGM204_Output($$) {
	my ($hash, $rawdata) = @_;
	my $name = $hash->{NAME};

#	my @raw = split('', $rawdata);
	my @raw = unpack ('C*', $rawdata);
	my $len = length($rawdata);
#	my $len = length(scalar @raw);
	my $retVal = undef;
	my $i = 0;
	my $max = 0;
	my $pos = $hash->{pos};

	# update readings first
	if ($pos < 32) {
		$max = 0 + $hash->{chars};
	
	} elsif ($pos < 64) {
		$max = 1 * $hash->{cpl} + $hash->{chars};
		
	} elsif ($pos < 96) {
		$max = 2 * $hash->{cpl} + $hash->{chars};
		
	} elsif ($pos < 128) {
		$max = 3 * $hash->{cpl} + $hash->{chars};
	}

	if ($hash->{failed} != 0) {
		return $retVal;
	}

	print "SPI_DOGM204_Output: $len $rawdata \n";
	
	eval {
		$i = 0;
		while ($i < $len && $pos < $max) {
		#	print 'SPI_DOGM204_Output: data ' . $raw[$i] . '\n';
			SPI_DOGM204_WriteByte($hash, DOGM204_REG_DATA, $raw[$i]);
			usleep(10);
			$i += 1;
			$pos += 1;
		}
		# fill the rest of the line with spaces to clear old text
		while ($pos < $max) {
		#	print 'SPI_DOGM204_Output: data 0x20\n';
			SPI_DOGM204_WriteByte($hash, DOGM204_REG_DATA, 0x20);
			usleep(10);
			$pos += 1;
		}
		$hash->{pos} = $pos;
		$retVal = $i;

		print "SPI_DOGM204_Output: $retVal \n";

	} or do {
		my $e = $@;
		print "ERROR: SPI_DOGM204_Output: exception ( $e )\n";
	};

	return $retVal;
}


my %DOGM204 = ();
my $DOGMRef = {%DOGM204};

$DOGMRef->{NAME} = 'DOGM204';
$DOGMRef->{initDone} = 0;

# Demo
SPI_CBerry28_Demo($DOGMRef, '/dev/spidev0.1');
