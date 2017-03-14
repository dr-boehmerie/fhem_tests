
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
	DOGM204_VISIBLE           =>2,       # channel 0 - channel 1,
	DOGM204_INFRARED          =>1,       # channel 1,
	DOGM204_FULLSPECTRUM      =>0,       # channel 0,

	# I2C address options
	DOGM204_ADDR_LOW          => '0x29',
	DOGM204_ADDR_FLOAT        => '0x39',    # Default address (pin left floating)
	DOGM204_ADDR_HIGH         => '0x49',

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

=head2 SPI_DOGM204_Initialize
	Title:		SPI_DOGM204_Initialize
	Function:	Implements the initialize function.
	Returns:	-
	Args:		named arguments:
				-argument1 => hash

=cut

sub SPI_DOGM204_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'SPI_DOGM204_Define';
	$hash->{AttrFn}   = 'SPI_DOGM204_Attr';
	$hash->{SetFn}    = 'SPI_DOGM204_Set';
	$hash->{GetFn}    = 'SPI_DOGM204_Get';
	$hash->{UndefFn}  = 'SPI_DOGM204_Undef';

	$hash->{AttrList} = 'do_not_notify:0,1 showtime:0,1 ' .
	                    'loglevel:0,1,2,3,4,5,6 poll_interval:1,2,5,10,20,30 ' . $readingFnAttributes;
}

=head2 SPI_DOGM204_Define
	Title:		SPI_DOGM204_Define
	Function:	Implements the define function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash
				-argument2 => string

=cut

sub SPI_DOGM204_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);

	my $name = $a[0];
	my $dev = $a[2];

	Log3 $name, 3, "SPI_DOGM204_Define start";
	my $msg = '';
	if( (@a < 3)) {
		$msg = 'wrong syntax: define <name> SPI_DOGM204 devicename';
		return undef;
	}

	# create default attributes
	$msg = CommandAttr(undef, $name . ' poll_interval 5');

	if ($msg) {
		Log (1, $msg);
		return $msg;
	}

	# check for existing spi device
	my $spiModulesLoaded = 0;
	$spiModulesLoaded = 1 if -e $dev;

	if ($spiModulesLoaded) {
		if (-r $dev && -w $dev) {
			$hash->{devDOGM204} = HiPi::Device::SPI->new(
				devicename	=> $dev,
				speed		=> SPI_SPEED_KHZ_500,
			#	busmode		=> SPI_MODE_3,
				bitsperword	=> 8,
				delay		=> 0,
			);
			Log3 $name, 3, "SPI_DOGM204_Define device created";

			$hash->{lines} = 4;
			$hash->{chars} = 20;
			$hash->{pos} = 0;
			$hash->{Timeout} = 200000;
			$hash->{logLevel} = 5;

			# Initialize Display
			SPI_DOGM204_InitController($hash);
			# Clear Display
			SPI_DOGM204_Clear($hash);

			my $host = hostname();
			my $address = get_local_ip_address();	#inet_ntoa(scalar gethostbyname( $host || 'localhost' ));
			
			# Welcome Message
			SPI_DOGM204_SetPos($hash, 0 * $hash->{chars});
			SPI_DOGM204_Output($hash, 'IP = ' . $address);
			SPI_DOGM204_SetPos($hash, 1 * $hash->{chars});
			SPI_DOGM204_Output($hash, 'Host = ' . $host);

			readingsSingleUpdate($hash, 'state', 'Initialized',1);
		} else {
			my @groups = split '\s', $(;
			return "$name :Error! $dev isn't readable/writable by user " . getpwuid( $< ) . " or group(s) " .
				getgrgid($_) . " " foreach(@groups);
		}

	} else {
		my $devices = HiPi::Device::SPI->get_device_list();
		return $name . ': Error! SPI device not found: ' . $dev . '. Please check that these kernelmodules are loaded: spi_bcm2708, spidev ' . $devices;
	}
	Log3 $name, $hash->{logLevel}, "SPI_DOGM204_Define end";

	return undef;
}

=head2 SPI_DOGM204_Attr
	Title:		SPI_DOGM204_Attr
	Function:	Implements AttrFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => array

=cut

sub SPI_DOGM204_Attr (@) {
	my (undef, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	Log3 $name, $hash->{logLevel}, "SPI_DOGM204_Attr: attr " . $attr . " val " . $val;
	if ($attr eq 'poll_interval') {
		my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;

		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'SPI_DOGM204_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	} elsif ($attr eq 'loglevel') {
		my $logLevel = (defined($val) && looks_like_number($val) && $val >= 0 && $val < 7) ? $val : 0;

		$hash->{logLevel} = $logLevel;
	}

	return ($msg) ? $msg : undef;
}

=head2 SPI_DOGM204_Poll
	Title:		SPI_DOGM204_Poll
	Function:	Start polling the sensor at interval defined in attribute
	Returns:	-
	Args:		named arguments:
				-argument1 => hash

=cut

sub SPI_DOGM204_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};

	# Read values
#	SPI_DOGM204_Get($hash);

	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'SPI_DOGM204_Poll', $hash, 0);
	}
}

=head2 SPI_DOGM204_Get
	Title:		SPI_DOGM204_Get
	Function:	Implements GetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_DOGM204_Get($) {
	my ( $hash ) = @_;
	my $name = $hash->{NAME};

#	my $lux = I2C_TSL2561_CalculateLux($hash);
#	readingsBeginUpdate($hash);
#	readingsBulkUpdate($hash,"luminosity",$lux);
#	readingsBulkUpdate($hash,"broadband",$hash->{broadband});
#	readingsBulkUpdate($hash,"ir",$hash->{ir});
#	readingsEndUpdate($hash,1);

	#readingsSingleUpdate($hash,"failures",ReadingsVal($hash->{NAME},"failures",0)+1,1);
}

=head2 SPI_DOGM204_Set
	Title:		SPI_DOGM204_Set
	Function:	Implements SetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_DOGM204_Set($@) {
	my ($hash, @a) = @_;

	my $name =$a[0];
	my $cmd = $a[1];
	my $val = $a[2];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}

	if ($cmd eq 'clear') {
		SPI_DOGM204_Clear($hash);
		return undef;
	}
	if ($cmd eq 'line') {
		SPI_DOGM204_SetPos($hash, $val * $hash->{chars});
		return undef;
	}
	if ($cmd eq 'pos') {
		SPI_DOGM204_SetPos($hash, $val);
		return undef;
	}
	if ($cmd eq 'output') {
		SPI_DOGM204_Output($hash, $val);
		return undef;
	}
	return 'Unhandled argument ' . $cmd;
}

=head2 SPI_DOGM204_Undef
	Title:		SPI_DOGM204_Undef
	Function:	Implements UndefFn function.
	Returns:	undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_DOGM204_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	$hash->{devDOGM204}->close( ).
	return undef;
}

=head2 SPI_DOGM204_WriteByte
	Title:		SPI_DOGM204_WriteByte
	Function:	Write 1 byte to spi device from given register.
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:	$hash			hash of device
				-argument2 => number:	$register

=cut

sub SPI_DOGM204_WriteByte($$$) {
	my ($hash, $register, $value) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	eval {
		Log3 $name, $hash->{logLevel},'SPI_DOGM204_WriteByte: start ';

		# ein Byte zum Display senden
		# 5 synchronization bits, read bit = 0
		my @temp = (0xF8, 0x00, 0x00);
		# register select
		if ($register != 0) {
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
		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_WriteByte: OUT ' . $value . ' -> ' . $temp[0] . ' ' . $temp[1] . ' ' . $temp[2];
		# transfer
		my @resp = unpack ('C3', $hash->{devDOGM204}->transfer( pack('C3', @temp) ));
		# wait
		#usleep(100)
		# debug
	#	Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_WriteByte: length = ' . length(scalar @resp);
		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_WriteByte: IN  ' . $resp[0] . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_WriteByte: IN0 ' . $resp[0];	# . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_WriteByte: IN1 ' . $resp[1];	# . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_WriteByte: IN2 ' . $resp[1];	# . ' ' . $resp[1] . ' ' . $resp[2];
		
		$retVal = $resp[0];
		
		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_WriteByte: ' . $retVal;
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_DOGM204_WriteByte: exception (' . $e . ')';
		$retVal = 0;
	};

	return $retVal;
}

sub SPI_DOGM204_ReadByte($$) {
	my ($hash, $register) = @_;
	my $name = $hash->{NAME};

	my $retVal = 0;

	eval {
		Log3 $name, $hash->{logLevel},'SPI_DOGM204_ReadByte: start ';

		# 5 synchronization bits, read bit = 1
		my @temp = (0xF8 | 0x04, 0x00, 0x00);
		# register select
		if ($register != 0) {
			$temp[0] |= 0x02;
		}
		# debug
		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_ReadByte: OUT ' . $temp[0] . ' ' . $temp[1] . ' ' . $temp[2];
		# transfer
		my @resp = unpack ('C3', $hash->{devDOGM204}->transfer( pack('C3', @temp) ));

		# debug
	#	Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_ReadByte: length = ' . length(scalar @resp);
		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_ReadByte: IN  ' . $resp[0] . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_ReadByte: IN0 ' . $resp[0];	# . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_ReadByte: IN1 ' . $resp[1];	# . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_ReadByte: IN2 ' . $resp[2];	# . ' ' . $resp[1] . ' ' . $resp[2];

		$retVal = $resp[2];
		
		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_ReadByte: ' . $retVal;
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_DOGM204_ReadByte: exception (' . $e . ')';
		$retVal = 0;
	};

	return $retVal;
}

sub SPI_DOGM204_WaitBusy($$) {
	my ($hash, $delay) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;
	my $timeout = $hash->{Timeout};

	eval {
		Log3 $name, $hash->{logLevel},'SPI_DOGM204_WaitBusy: ' . $delay;

		while (!defined($retVal) && $timeout > 0) {
			# read data
			my $resp = SPI_DOGM204_ReadByte($hash, 0);
			# test flag
			#if (resp[2] & 0x1) == 0:
			if (($resp & 1) == 0) {
				$retVal = 1;
			} else {
				# wait
				usleep($delay);
			}
			$timeout -= $delay;
		}
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_DOGM204_WaitBusy: exception (' . $e . ')';
	};
	return $retVal;
}

sub SPI_DOGM204_InitController($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	eval {
		Log3 $name, $hash->{logLevel},'SPI_DOGM204_InitController:';

		# function set: 8 bit data length, RE=1, REV=0
		SPI_DOGM204_WriteByte($hash, 0, 0x3A);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# ext. function set: 5 dot font, 4 line display
		SPI_DOGM204_WriteByte($hash, 0, 0x09);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# entry mode set: bottom view
		SPI_DOGM204_WriteByte($hash, 0, 0x06);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# bias setting
		SPI_DOGM204_WriteByte($hash, 0, 0x1E);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# function set: 8 bit data length, RE=0, IS=1
		SPI_DOGM204_WriteByte($hash, 0, 0x39);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# internal osc
		SPI_DOGM204_WriteByte($hash, 0, 0x1B);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# divider on, set value
		SPI_DOGM204_WriteByte($hash, 0, 0x6E);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# booster on, set contrast
		SPI_DOGM204_WriteByte($hash, 0, 0x57);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# set contrast
		SPI_DOGM204_WriteByte($hash, 0, 0x72);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# function set: 8 bit data length, RE=0, IS=0
		SPI_DOGM204_WriteByte($hash, 0, 0x38);
		SPI_DOGM204_WaitBusy($hash, 1000);
		# display on, cursor on, blink on;
		#SPI_DOGM204_WriteByte($hash, 0, 0x0F);
		# display on
		SPI_DOGM204_WriteByte($hash, 0, 0x08 | 0x04);
		SPI_DOGM204_WaitBusy($hash, 10000);

		$retVal = 1;

		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_InitController: ' . $retVal;
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_DOGM204_InitController: exception (' . $e . ')';
	};

	return $retVal;
}

sub SPI_DOGM204_Clear($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	eval {
		Log3 $name, $hash->{logLevel},'SPI_DOGM204_Clear:';

		# clear display
		SPI_DOGM204_WriteByte($hash, 0, 0x01);
		# wait
		SPI_DOGM204_WaitBusy($hash, 2000);

		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'text0', '');
		readingsBulkUpdate($hash, 'text1', '');
		readingsBulkUpdate($hash, 'text2', '');
		readingsBulkUpdate($hash, 'text3', '');
		readingsEndUpdate($hash, 1);	

		$retVal = 1;

		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_Clear: ' . $retVal;
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_DOGM204_Clear: exception (' . $e . ')';
	};

	return $retVal;
}

sub SPI_DOGM204_SetPos($$) {
	my ($hash, $pos) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	eval {
		Log3 $name, $hash->{logLevel},'SPI_DOGM204_SetPos: ' . $pos;

		# set DDRAM address
		if ($pos >= 0 and $pos < ($hash->{lines} * $hash->{chars})) {
			my $line = $pos / $hash->{chars};
			$pos = $pos % $hash->{chars};
			$hash->{pos} = $line * 32 + $pos;
			
			Log3 $name, $hash->{logLevel},'SPI_DOGM204_SetPos: ' . $line . ' / ' . $pos;
			
			SPI_DOGM204_WriteByte($hash, 0, 0x80 + $hash->{pos});
			usleep(100);
			
			$retVal = 1;
		} else {
			$retVal = 0;
		}

		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_SetPos: ' . $retVal;
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_DOGM204_SetPos: exception (' . $e . ')';
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

	eval {
		Log3 $name, $hash->{logLevel},'SPI_DOGM204_Output: ' . $len . ' ' . $rawdata;
		
		if ($hash->{pos} < 32) {
			$max = 1 * $hash->{chars};
			readingsSingleUpdate($hash,'text0',$rawdata,1);
		
		} elsif ($hash->{pos} < 64) {
			$max = 2 * $hash->{chars};
			readingsSingleUpdate($hash,'text1',$rawdata,1);
			
		} elsif ($hash->{pos} < 96) {
			$max = 3 * $hash->{chars};
			readingsSingleUpdate($hash,'text2',$rawdata,1);
			
		} elsif ($hash->{pos} < 128) {
			$max = 4 * $hash->{chars};
			readingsSingleUpdate($hash,'text3',$rawdata,1);

		}
			

		$i = 0;
		while ($i < $len && $i < $max) {
			Log3 $name, $hash->{logLevel},'SPI_DOGM204_Output: data ' . $raw[$i];
			SPI_DOGM204_WriteByte($hash, 1, $raw[$i]);
			usleep(10);
			$i += 1;
		}
		# Rest mit Leerzeichen füllen
		while ($i < $max) {
			Log3 $name, $hash->{logLevel},'SPI_DOGM204_Output: data 32';
			SPI_DOGM204_WriteByte($hash, 1, 32);
			usleep(10);
			$i += 1;
		}
		$hash->{pos} += $len;
		$retVal = $i;

		Log3 $name, $hash->{logLevel}, 'SPI_DOGM204_Output: ' . $retVal;
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_DOGM204_Output: exception (' . $e . ')';
	};

	return $retVal;
}

1;

=pod
=begin html

<a name="I2C_TSL2561"></a>
<h3>I2C_TSL2561</h3>
<ul>
  <a name="I2C_TSL2561"></a>
  <p>
    With this module you can read values from the digital luminosity sensor TSL2561
    via the i2c bus on Raspberry Pi.<br><br>

    Before you can use the module on the Raspberry Pi you must load the I2C kernel
    modules.<br>
    Add these two lines to your <b>/etc/modules</b> file to load the kernel modules
    automatically when booting your Raspberry Pi.<br>
    <code><pre>
     i2c-bcm2708
     i2c-dev
    </pre></code>

    <b>Please note:</b><br>
    For the i2c communication, the perl modules HiPi::Device::I2C
    are required.<br>
    For a simple automated installation:<br>
    <code>wget http://raspberry.znix.com/hipifiles/hipi-install<br>
    perl hipi-install</code><br><br>

  <p>

  <b>Define</b>
  <ul>
    <code>define TSL2561 I2C_TSL2561 &lt;I2C device&gt; &lt;I2C address&gt</code><br>
    <br>
    Examples:
    <pre>
      define TSL2561 I2C_TSL2561 /dev/i2c-0 0x39
      attr TSL2561 poll_interval 5
    </pre>
  </ul>

  <a name="I2C_TSL2561attr"></a>
  <b>Attributes</b>
  <ul>
    <li>poll_interval<br>
      Set the polling interval in minutes to query the sensor for new measured
      values.<br>
      Default: 5, valid values: 1, 2, 5, 10, 20, 30<br><br>
    </li>
    <li>integrationTime<br>
      time in ms the sensor takes to measure the light.<br>
      Default: 13, valid values: 13, 101, 402
      see this <a href="https://learn.sparkfun.com/tutorials/tsl2561-luminosity-sensor-hookup-guide/using-the-arduino-library">tutorial</a>
      for more details
    </li>
    <li>gain<br>
      gain factor
      Default: 1, valid values: 1, 16
    </li>
    <li>autoGain<br>
      enable auto gain
      Default: 1, valid values: 0, 1
      if set to 1,the gain parameter is set automatically depending on light conditions
    </li>
</ul>
  <br>
</ul>


=end html

=cut
