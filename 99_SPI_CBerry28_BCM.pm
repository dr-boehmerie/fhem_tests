
package main;

use strict;
use warnings;

use Device::BCM2835;

use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
use Error qw(:try);
use Sys::Hostname;
use Socket;	# für die IP-Adresse
use IO::Socket::INET;


use constant {
#color modes (color depths) { CM_262K, CM_65K };
	CM_262K			=> 0,
	CM_65K			=> 1,

# TFT dimensions
	DISPLAY_WIDTH	=> 320,
	DISPLAY_HEIGHT	=> 240,
	PICTURE_PIXELS	=> ( 320 * 240 ),

# ST register -> see datasheet ST7789
	NOP				=> 0x00,
	SWRESET 		=> 0x01,
	RDDID 			=> 0x04,
	RDDST 			=> 0x09,
	RDDPM 			=> 0x0A,
	RDDMADCTL 		=> 0x0B,
	RDDCOLMOD 		=> 0x0C,
	RDDIM 			=> 0x0D,
	RDDSM 			=> 0x0E,
	RDDSDR 			=> 0x0F,
	SLPIN 			=> 0x10,
	SLPOUT			=> 0x11,
	PTLON			=> 0x12,
	NORON			=> 0x13,
	INVOFF			=> 0x20,
	INVON			=> 0x21,
	GAMSET			=> 0x26,
	DISPOFF			=> 0x28,
	DISPON			=> 0x29,
	CASET			=> 0x2A,
	RASET			=> 0x2B,
	RAMWR			=> 0x2C,
	RAMRD			=> 0x2E,
	PTLAR			=> 0x30,
	VSCRDEF			=> 0x33,
	TEOFF			=> 0x34,
	TEON			=> 0x35,
	MADCTL			=> 0x36,
	VSCRSADD		=> 0x37,
	IDMOFF			=> 0x38,
	IDMON			=> 0x39,
	COLMOD			=> 0x3A,
	RAMWRC			=> 0x3C,
	RAMRDC			=> 0x3E,
	TESCAN			=> 0x44,
	RDTESCAN		=> 0x45,
	WRDISBV			=> 0x51,
	RDDISBV			=> 0x52,
	WRCTRLD			=> 0x53,
	RDCTRLD			=> 0x54,
	WRCACE			=> 0x55,
	RDCABC			=> 0x56,
	WRCABCMB		=> 0x5E,
	RDCABCMB		=> 0x5F,
	RDID1			=> 0xDA,
	RDID2			=> 0xDB,
	RDID3			=> 0xDC,

	RAMCTRL			=> 0xB0,
	RGBCTRL			=> 0xB1,
	PORCTRL			=> 0xB2,
	FRCTRL1 		=> 0xB3,
	GCTRL			=> 0xB7,
	DGMEN			=> 0xBA,
	VCOMS			=> 0xBB,
	LCMCTRL			=> 0xC0,
	IDSET			=> 0xC1,
	VDVVRHEN		=> 0xC2,
	VRHS			=> 0xC3,
	VDVSET			=> 0xC4,
	VCMOFSET		=> 0xC5,
	FRCTRL2			=> 0xC6,
	CABCCTRL		=> 0xC7,
	REGSEL1			=> 0xC8,
	REGSEL2 		=> 0xCA,
	PWCTRL1			=> 0xD0,
	VAPVANEN		=> 0xD0,
	PVGAMCTRL		=> 0xE0,
	NVGAMCTRL		=> 0xE1,
	DGMLUTR			=> 0xE2,
	DGMLUTB			=> 0xE3,
	GATECTRL		=> 0xE4,
	PWCTRL2			=> 0xE8,
	EQCTRL			=> 0xE9,
	PROMCTRL		=> 0xEC,
	PROMEN			=> 0xFA,
	NVMSET			=> 0xFC,
	PROMACT			=> 0xFE,

#	MOSI			=> RPI_V2_GPIO_P1_19,
#	SCLK			=> RPI_V2_GPIO_P1_23,
#	SPI_CE0			=> RPI_V2_GPIO_P1_24,
#	PIN_ST_RST		=> RPI_PAD1_PIN_22,	#RPI_V2_GPIO_P1_22,
#	PIN_ST_RS		=> RPI_PAD1_PIN_15,	#RPI_V2_GPIO_P1_15,
#	PIN_BL_PWM		=> RPI_PAD1_PIN_12,	#RPI_V2_GPIO_P1_12,

# PWM settings
	PWM_CHANNEL		=> 0,
	PWM_RANGE		=> 255,

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
sub SPI_CBerry28_Initialize($);
sub SPI_CBerry28_Define($$);
sub SPI_CBerry28_Attr(@);
sub SPI_CBerry28_Poll($);
sub SPI_CBerry28_Set($@);
sub SPI_CBerry28_Get($);
sub SPI_CBerry28_Undef($$);
sub SPI_CBerry28_WriteByte($$$);
sub SPI_CBerry28_ReadByte($$);
sub SPI_CBerry28_WaitBusy($$);
sub SPI_CBerry28_InitController($);
sub SPI_CBerry28_Clear($);
sub SPI_CBerry28_SetPos($$);
sub SPI_CBerry28_Output($$);



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

=head2 SPI_CBerry28_Initialize
	Title:		SPI_CBerry28_Initialize
	Function:	Implements the initialize function.
	Returns:	-
	Args:		named arguments:
				-argument1 => hash

=cut

sub SPI_CBerry28_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'SPI_CBerry28_Define';
	$hash->{AttrFn}   = 'SPI_CBerry28_Attr';
	$hash->{SetFn}    = 'SPI_CBerry28_Set';
	$hash->{GetFn}    = 'SPI_CBerry28_Get';
	$hash->{UndefFn}  = 'SPI_CBerry28_Undef';

	$hash->{AttrList} = 'do_not_notify:0,1 showtime:0,1 initDone:0,1 ' .
	                    'loglevel:0,1,2,3,4,5,6 poll_interval:1,2,5,10,20,30 ' . $readingFnAttributes;
}

=head2 SPI_CBerry28_Define
	Title:		SPI_CBerry28_Define
	Function:	Implements the define function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash
				-argument2 => string

=cut

sub SPI_CBerry28_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);

	my $name = $a[0];
	my $dev = $a[2];

	Log3 $name, 3, "SPI_CBerry28_Define start";
	my $msg = '';
	if( (@a < 3)) {
		$msg = 'wrong syntax: define <name> SPI_CBerry28 spi_device [gpio_rst_pin gpio_rs_pin [gpio_pwm_pin]]';
		return undef;
	}

#	$hash->{lines} = 4;
#	$hash->{chars} = 20;
#	$hash->{pos} = 0;
#	$hash->{Timeout} = 200000;
	$hash->{logLevel} = 5;
	$hash->{initDone} = 0;

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
			eval {
				my $ret = Device::BCM2835::init();
				if ($ret == 1) {
					# Init SPI
					Device::BCM2835::spi_begin();
					Device::BCM2835::spi_setBitOrder(Device::BCM2835::BCM2835_SPI_BIT_ORDER_MSBFIRST);		# The default
					Device::BCM2835::spi_setDataMode(Device::BCM2835::BCM2835_SPI_MODE0);					# The default
					Device::BCM2835::spi_setClockDivider(Device::BCM2835::BCM2835_SPI_CLOCK_DIVIDER_65536);	# The default
					Device::BCM2835::spi_chipSelect(Device::BCM2835::BCM2835_SPI_CS0);						# The default
					Device::BCM2835::spi_setChipSelectPolarity(Device::BCM2835::BCM2835_SPI_CS0, 0);		# the default
					Log3 $name, 3, "SPI_CBerry28_Define SPI device created" . $dev;

					# Control Pins using BCM2835
					# RST = 22
					$hash->{pinRST} = &Device::BCM2835::RPI_GPIO_P1_22;
					Device::BCM2835::gpio_fsel($hash->{pinRST}, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
					Device::BCM2835::gpio_write($hash->{pinRST}, 0);
					Log3 $name, 3, "SPI_CBerry28_Define pin RST set to output: " . PIN_ST_RST;
					# RS = 15
					$hash->{pinRS} = &Device::BCM2835::RPI_GPIO_P1_15;
					Device::BCM2835::gpio_fsel($hash->{pinRS}, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
					Device::BCM2835::gpio_write($hash->{pinRS}, 0);
					Log3 $name, 3, "SPI_CBerry28_Define pin RS set to output: " . PIN_ST_RS;
					# PWM = 12
					$hash->{pinPWM} = &Device::BCM2835::RPI_GPIO_P1_12;
					Device::BCM2835::gpio_fsel($hash->{pinPWM}, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
					Device::BCM2835::gpio_write($hash->{pinPWM}, 0);
					Log3 $name, 3, "SPI_CBerry28_Define pin PWM set to output: " . PIN_BL_PWM;
					
					$hash->{initDone} = 1;
				}
			} or do {
				my $e = $@;
				Log3 $name, 1, 'ERROR: SPI_CBerry28_Define: Hardware setup failed (' . $e . ')';
				return "$name :Error! Hardware setup failed!";
			};
			
			if ($hash->{initDone} == 1) {
				# Initialize Display
				SPI_CBerry28_Init($hash);
				# Clear Display
			#	SPI_CBerry28_Clear($hash);

				my $host = hostname();
				my $address = get_local_ip_address();	#inet_ntoa(scalar gethostbyname( $host || 'localhost' ));

				# Welcome Message
				SPI_CBerry28_SetPos($hash, 0 * $hash->{chars});
				SPI_CBerry28_Output($hash, 'IP = ' . $address);
				SPI_CBerry28_SetPos($hash, 1 * $hash->{chars});
				SPI_CBerry28_Output($hash, 'Host = ' . $host);

				readingsSingleUpdate($hash, 'state', 'Initialized',1);
			} else {
				Log3 $name, 1, 'ERROR: SPI_CBerry28_Define: Hardware setup failed';
				return "$name :Error! Hardware setup failed!";
			}
		} else {
			my @groups = split '\s', $(;
			return "$name :Error! $dev isn't readable/writable by user " . getpwuid( $< ) . " or group(s) " .
				getgrgid($_) . " " foreach(@groups);
		}
	} else {
		return $name . ': Error! SPI device not found: ' . $dev . '. Please check that these kernelmodules are loaded: spi_bcm2708, spidev';
	}
	Log3 $name, $hash->{logLevel}, "SPI_CBerry28_Define end";

	return undef;
}

=head2 SPI_CBerry28_Attr
	Title:		SPI_CBerry28_Attr
	Function:	Implements AttrFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => array

=cut

sub SPI_CBerry28_Attr (@) {
	my (undef, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	Log3 $name, $hash->{logLevel}, "SPI_CBerry28_Attr: attr " . $attr . " val " . $val;
	if ($attr eq 'poll_interval') {
		my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;

		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'SPI_CBerry28_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	} elsif ($attr eq 'loglevel') {
		my $logLevel = (defined($val) && looks_like_number($val) && $val >= 0 && $val < 7) ? $val : 0;

		$hash->{logLevel} = $logLevel;
	}

	return ($msg) ? $msg : undef;
}

=head2 SPI_CBerry28_Poll
	Title:		SPI_CBerry28_Poll
	Function:	Start polling the sensor at interval defined in attribute
	Returns:	-
	Args:		named arguments:
				-argument1 => hash

=cut

sub SPI_CBerry28_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};

	# Read values
#	SPI_CBerry28_Get($hash);

	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'SPI_CBerry28_Poll', $hash, 0);
	}
}

=head2 SPI_CBerry28_Get
	Title:		SPI_CBerry28_Get
	Function:	Implements GetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_CBerry28_Get($) {
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

=head2 SPI_CBerry28_Set
	Title:		SPI_CBerry28_Set
	Function:	Implements SetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_CBerry28_Set($@) {
	my ($hash, @a) = @_;

	my $name =$a[0];
	my $cmd = $a[1];
	my $val = $a[2];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}

	if ($cmd eq 'clear') {
		SPI_CBerry28_Clear($hash);
		return undef;
	}
	if ($cmd eq 'line') {
		SPI_CBerry28_SetPos($hash, $val * $hash->{chars});
		return undef;
	}
	if ($cmd eq 'pos') {
		SPI_CBerry28_SetPos($hash, $val);
		return undef;
	}
	if ($cmd eq 'output') {
		SPI_CBerry28_Output($hash, $val);
		return undef;
	}
	return 'Unhandled argument ' . $cmd;
}

=head2 SPI_CBerry28_Undef
	Title:		SPI_CBerry28_Undef
	Function:	Implements UndefFn function.
	Returns:	undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub SPI_CBerry28_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
#	$hash->{devSPI}->close( ).
	if ($hash->{initDone} == 1) {
		Device::BCM2835::spi_end();
	}
	return undef;
}

=head2 SPI_CBerry28_WriteByte
	Title:		SPI_CBerry28_WriteByte
	Function:	Write 1 byte to spi device from given register.
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:	$hash			hash of device
				-argument2 => number:	$register

=cut

sub SPI_CBerry28_WriteByte($$$) {
	my ($hash, $register, $value) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	try {
		Log3 $name, $hash->{logLevel},'SPI_CBerry28_WriteByte: start ';

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
		Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteByte: OUT ' . $value . ' -> ' . $temp[0] . ' ' . $temp[1] . ' ' . $temp[2];
		# transfer
	#	my @resp = unpack ('C3', $hash->{devSPI}->transfer( pack('C3', @temp) ));
		# wait
		#usleep(100)
		# debug
	#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteByte: length = ' . length(scalar @resp);
#		Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteByte: IN  ' . $resp[0] . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteByte: IN0 ' . $resp[0];	# . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteByte: IN1 ' . $resp[1];	# . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteByte: IN2 ' . $resp[1];	# . ' ' . $resp[1] . ' ' . $resp[2];

	#	$retVal = $resp[0];
		$retVal = 0;

		Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteByte: ' . $retVal;
	} catch Error with {
		Log3 $name, 1, 'ERROR: SPI_CBerry28_WriteByte: spi-transfer failure';
		$retVal = 0;
	};

	return $retVal;
}

sub SPI_CBerry28_ReadByte($$) {
	my ($hash, $register) = @_;
	my $name = $hash->{NAME};

	my $retVal = 0;

	try {
		Log3 $name, $hash->{logLevel},'SPI_CBerry28_ReadByte: start ';

		# 5 synchronization bits, read bit = 1
		my @temp = (0xF8 | 0x04, 0x00, 0x00);
		# register select
		if ($register != 0) {
			$temp[0] |= 0x02;
		}
		# debug
		Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_ReadByte: OUT ' . $temp[0] . ' ' . $temp[1] . ' ' . $temp[2];
		# transfer
	#	my @resp = unpack ('C3', $hash->{devSPI}->transfer( pack('C3', @temp) ));

		# debug
	#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_ReadByte: length = ' . length(scalar @resp);
#		Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_ReadByte: IN  ' . $resp[0] . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_ReadByte: IN0 ' . $resp[0];	# . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_ReadByte: IN1 ' . $resp[1];	# . ' ' . $resp[1] . ' ' . $resp[2];
	#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_ReadByte: IN2 ' . $resp[2];	# . ' ' . $resp[1] . ' ' . $resp[2];

	#	$retVal = $resp[2];
		$retVal = 0;

		Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_ReadByte: ' . $retVal;
	} catch Error with {
		Log3 $name, 1, 'ERROR: SPI_CBerry28_ReadByte: spi-transfer failure';
		$retVal = 0;
	};

	return $retVal;
}

sub SPI_CBerry28_Clear($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_Clear:';

	# clear display
#		SPI_CBerry28_WriteByte($hash, 0, 0x01);
	# wait
#		SPI_CBerry28_WaitBusy($hash, 2000);

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'text0', '');
	readingsBulkUpdate($hash, 'text1', '');
	readingsBulkUpdate($hash, 'text2', '');
	readingsBulkUpdate($hash, 'text3', '');
	readingsEndUpdate($hash, 1);

	$retVal = 1;

	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_Clear: ' . $retVal;

	return $retVal;
}

sub SPI_CBerry28_SetPos($$) {
	my ($hash, $pos) = @_;
	my $name = $hash->{NAME};

	my $retVal = undef;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetPos: ' . $pos;

	# set DDRAM address
	if ($pos >= 0 and $pos < ($hash->{lines} * $hash->{chars})) {
		my $line = $pos / $hash->{chars};
		$pos = $pos % $hash->{chars};
		$hash->{pos} = $line * 32 + $pos;

		Log3 $name, $hash->{logLevel},'SPI_CBerry28_SetPos: ' . $line . ' / ' . $pos;

#		SPI_CBerry28_WriteByte($hash, 0, 0x80 + $hash->{pos});
		usleep(100);

		$retVal = 1;
	} else {
		$retVal = 0;
	}

	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_SetPos: ' . $retVal;

	return $retVal;
}

sub SPI_CBerry28_Output($$) {
	my ($hash, $rawdata) = @_;
	my $name = $hash->{NAME};

#	my @raw = split('', $rawdata);
	my @raw = unpack ('C*', $rawdata);
	my $len = length($rawdata);
#	my $len = length(scalar @raw);
	my $retVal = undef;
	my $i = 0;
	my $max = 0;

	Log3 $name, $hash->{logLevel},'SPI_CBerry28_Output: ' . $len . ' ' . $rawdata;

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
		Log3 $name, $hash->{logLevel},'SPI_CBerry28_Output: data ' . $raw[$i];
#		SPI_CBerry28_WriteByte($hash, 1, $raw[$i]);
#		usleep(10);
		$i += 1;
	}
	# Rest mit Leerzeichen füllen
	while ($i < $max) {
		Log3 $name, $hash->{logLevel},'SPI_CBerry28_Output: data 32';
#		SPI_CBerry28_WriteByte($hash, 1, 32);
#		usleep(10);
		$i += 1;
	}
	$hash->{pos} += $len;
	$retVal = $i;

	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_Output: ' . $retVal;

	return $retVal;
}

# write byte to register
sub SPI_CBerry28_WriteReg($$)
{
	my ($hash, $val) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteReg: ' . $val;

	my @temp = ($val);

	eval {
	#	bcm2835_gpio_write( ST_RS, LOW );
	#	$hash->{pinRS}->value(0);
	#	HiPi::Wiring::digitalWrite(ST_RS, 0);
	Device::BCM2835::gpio_write($hash->{pinRS}, 0);
	#	my @resp = unpack ('C1', $hash->{devSPI}->transfer( pack('C1', @temp) ));
		my $resp = Device::BCM2835::spi_transfer( pack('C1', @temp) )

	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_CBerry28_WriteReg: spi-transfer failure (' . $e . ')';
	};
}

# write byte to tft
sub SPI_CBerry28_WriteData($$)
{
	my ($hash, $val) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteData: ' . $val;

	my @temp = ($val);

	eval {
	#	bcm2835_gpio_write( ST_RS, HIGH );
	#	$hash->{pinRS}->value(1);
	#	HiPi::Wiring::digitalWrite(ST_RS, 1);
		Device::BCM2835::gpio_write($hash->{pinRS}, 1);
	
	#	my @resp = unpack ('C1', $hash->{devSPI}->transfer( pack('C1', @temp) ));
		my $resp = Device::BCM2835::spi_transfer( pack('C1', @temp) )
		
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_CBerry28_WriteData: spi-transfer failure (' . $e . ')';
	};
}

# write 3 * 'count'-bytes to tft
sub SPI_CBerry28_WriteMultiData($$@)
{
	my ($hash, $cnt, @a) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WriteMultiData: ' . $cnt;

	eval {
	#	bcm2835_gpio_write( ST_RS, HIGH );
	#	$hash->{pinRS}->value(1);
	#	HiPi::Wiring::digitalWrite(ST_RS, 1);
		Device::BCM2835::gpio_write($hash->{pinRS}, 1);

		# $cnt
	#	my @resp = unpack ('C' . $cnt, $hash->{devSPI}->transfer( pack('C' . $cnt, @a) ));
		my $resp = Device::BCM2835::spi_transfer( pack('C' . $cnt, @a) )
	} or do {
		my $e = $@;
		Log3 $name, 1, 'ERROR: SPI_CBerry28_WriteMultiData: spi-transfer failure (' . $e . ')';
	};
}

# write command to a register
sub SPI_CBerry28_SetRegister($$$@)
{
	my ($hash, $reg, $cnt, @a) = @_;
#	my $reg = $a[0];
#	my $cnt = $a[1];
#	my $i;

	SPI_CBerry28_WriteReg ($hash, $reg);

#	for (i = 0; i < $cnt; i++) {
#		SPI_CBerry28_WriteData ($hash, $a[i]);
#	}
	SPI_CBerry28_WriteMultiData ($hash, @a);
}

# define area of frame memory where MCU can access
sub SPI_CBerry28_SetRow($$$)
{
	my ($hash, $row_start, $row_end) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_SetRow: ' . $row_start . ' : ' . $row_end;

	SPI_CBerry28_SetRegister ($hash,
		RASET, 4,
		($row_start >> 16) & 0xFFFF, $row_start & 0xFFFF,
		($row_end >> 16) & 0xFFFF, $row_end & 0xFFFF);
}

sub SPI_CBerry28_SetColumn($$$)
{
	my ($hash, $col_start, $col_end) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_SetColumn: ' . $col_start . ' : ' . $col_end;

	SPI_CBerry28_SetRegister ($hash,
		CASET, 4,
		($col_start >> 16) & 0xFFFF, $col_start & 0xFFFF,
		($col_end >> 16) & 0xFFFF, $col_end & 0xFFFF);
}

# initialization of ST7789
sub SPI_CBerry28_InitTFTcontroller($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_InitTFTcontroller:';

	# *************** wakeup display
	SPI_CBerry28_SetRegister($hash, SLPOUT, 0);
	usleep(120 * 1000);

	# *************** display and color format setting

	# write data from top-left to bottom-right
	SPI_CBerry28_SetRegister($hash, MADCTL, 1, 0xA0);	# 0x00

	if (CM_262K == 1) {
		# 18bit/pixel
		# 262K-colors (RGB 6-6-6)
		SPI_CBerry28_SetRegister($hash, COLMOD, 1, 0x06);
	} else {
		# 16bit/pixel
		# 65K-colors (RGB 5-6-5)
		SPI_CBerry28_SetRegister($hash, COLMOD, 1, 0x05);
	}

	# *************** ST7789 porch setting

	# seperate porch control = disabled
	# front porch in normal mode  = 13 CLK pulse
	# back porch in normal mode   = 13 CLK pulse
	# front porch in idle mode    =  3 CLK pulse
	# back porch in idle mode     =  3 CLK pulse
	# front porch in partial mode =  3 CLK pulse
	# back porch in partial mode  =  3 CLK pulse
	SPI_CBerry28_SetRegister($hash, PORCTRL, 5, 0x0C, 0x0C, 0x00, 0x33, 0x33);

	# *************** ST7789 Power setting

	# VGH =  12.26V
	# VGL = -10.43V
	SPI_CBerry28_SetRegister($hash, GCTRL, 1, 0x35 );

	# VDV and VRH register value comes from command line
	SPI_CBerry28_SetRegister($hash, VDVVRHEN, 1, 0x1F );

	# VAP = 4.7 + Vcom + Vcom_offset + 0.5*VDV
	SPI_CBerry28_SetRegister($hash, VRHS, 1, 0x2C );

	# VDV = 0V
	SPI_CBerry28_SetRegister($hash, VDVSET, 1, 0x01 );

	# Vcom = 0.875V
	SPI_CBerry28_SetRegister($hash, VCOMS, 1, 0x17 );

	# Vcom_offset = 0V
	SPI_CBerry28_SetRegister($hash, VCMOFSET, 1, 0x20 );

	# AVDD =  6.6V
	# AVCL = -4.8V
	# VDS  =  2.3V
	SPI_CBerry28_SetRegister($hash, PWCTRL1, 2, 0xA4, 0xA1);

	# *************** ST7789 gamma setting

	SPI_CBerry28_SetRegister($hash, PVGAMCTRL, 14, 0xD0, 0x00, 0x14, 0x15, 0x13, 0x2C, 0x42, 0x43, 0x4E, 0x09, 0x16, 0x14, 0x18, 0x21);
	SPI_CBerry28_SetRegister($hash, NVGAMCTRL, 14, 0xD0, 0x00, 0x14, 0x15, 0x13, 0x0B, 0x43, 0x55, 0x53, 0x0C, 0x17, 0x14, 0x23, 0x20);

	# *************** miscellaneous settings

	# define area (start row, end row, start column, end column) of frame memory where MCU can access
	SPI_CBerry28_setRow($hash, 0, DISPLAY_HEIGHT - 1 );
	SPI_CBerry28_setColumn($hash, 0, DISPLAY_WIDTH - 1 );

	# *************** display on
	SPI_CBerry28_SetRegister($hash, DISPON, 0);
}

# initialization of GPIO and SPI
sub SPI_CBerry28_InitBoard ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	# *************** set the pins to be an output and turn them on

#	bcm2835_gpio_fsel( ST_RS, BCM2835_GPIO_FSEL_OUTP );
#	bcm2835_gpio_write( ST_RS, HIGH );

#	bcm2835_gpio_fsel( ST_RST, BCM2835_GPIO_FSEL_OUTP );
#	bcm2835_gpio_write( ST_RST, HIGH );

	# *************** set pins for PWM

#	bcm2835_gpio_fsel( BL_PWM, BCM2835_GPIO_FSEL_ALT5 );

	# Clock divider is set to 16.
	# 1.2MHz/1024 = 1171.875Hz
#	bcm2835_pwm_set_clock(BCM2835_PWM_CLOCK_DIVIDER_16);
#	bcm2835_pwm_set_mode(PWM_CHANNEL, 1, 1);
#	bcm2835_pwm_set_range(PWM_CHANNEL, PWM_RANGE);

	# *************** set pins for SPI

#	bcm2835_gpio_fsel(MOSI, BCM2835_GPIO_FSEL_ALT0);
#	bcm2835_gpio_fsel(SCLK, BCM2835_GPIO_FSEL_ALT0);
#	bcm2835_gpio_fsel(SPI_CE0, BCM2835_GPIO_FSEL_ALT0);

	# set the SPI CS register to the some sensible defaults
#	volatile uint32_t* paddr = bcm2835_spi0 + BCM2835_SPI0_CS/8;
#	bcm2835_peri_write( paddr, 0 ); # All 0s

	# clear TX and RX fifos
#	bcm2835_peri_write_nb( paddr, BCM2835_SPI0_CS_CLEAR );

#	bcm2835_spi_setBitOrder( BCM2835_SPI_BIT_ORDER_MSBFIRST );
#	bcm2835_spi_setDataMode( BCM2835_SPI_MODE0 );
#	bcm2835_spi_setClockDivider( BCM2835_SPI_CLOCK_DIVIDER_2 );
#	bcm2835_spi_chipSelect( BCM2835_SPI_CS0 );
#	bcm2835_spi_setChipSelectPolarity( BCM2835_SPI_CS0, LOW );
}


# hard reset of the tft controller
sub SPI_CBerry28_HardReset($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_HardReset:';

	usleep(1 * 1000);
#	bcm2835_gpio_write( ST_RST, LOW );
#	$hash->{pinRST}->value(0);
#	HiPi::Wiring::digitalWrite(ST_RST, 0);
	Device::BCM2835::gpio_write($hash->{pinRST}, 0);
	usleep(10 * 1000);
#	bcm2835_gpio_write( ST_RST, HIGH );
#	$hash->{pinRST}->value(1);
	Device::BCM2835::gpio_write($hash->{pinRST}, 1);
#	HiPi::Wiring::digitalWrite(ST_RST, 1);
	usleep(120 * 1000);
}

# show the BMP picture on the TFT screen
#sub SPI_CBerry28_WritePicture666($$@);
#{
#	my ($hash, $cnt, @a) = @_;
#	my $name = $hash->{NAME};
#
#	# debug
#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WritePicture666: ' . $cnt;
#
#	if ($hash->{initDone} && $hash->{initDone} == 1) {
#		SPI_CBerry28_WriteReg($hash, RAMWR);
#
#		SPI_CBerry28_WriteMultiData($hash, $cnt, @a);
#	}
#}

#sub SPI_CBerry28_WritePicture565($$@)
#{
#	my ($hash, $cnt, @a) = @_;
#	my $name = $hash->{NAME};
#
#	# debug
#	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_WritePicture565: ' . $cnt;
#
#	if ($hash->{initDone} && $hash->{initDone} == 1) {
#		SPI_CBerry28_WriteReg($hash, RAMWR);
#
#		SPI_CBerry28_WriteMultiData($hash, $cnt, @a);
#	}
#}

# set PWM value for backlight -> 0 (0% PWM) - 1024 (100% PWM)
sub SPI_CBerry28_setBacklightPWM($$)
{
	my ($hash, $val) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_setBacklightPWM: ' . $val;

	if ($hash->{initDone} && $hash->{initDone} == 1) {
	#	bcm2835_pwm_set_data( PWM_CHANNEL, BL_value );
		# TODO: PWM value
		if ($val > 0) {
		#	$hash->{pinPWM}->value(1);
			Device::BCM2835::gpio_write($hash->{pinPWM}, 1);
		} else {
		#	$hash->{pinPWM}->value(0);
			Device::BCM2835::gpio_write($hash->{pinPWM}, 1);
		}
	#	HiPi::Wiring::pwmWrite(BL_PWM, $val)
	}
}

sub SPI_CBerry28_InitController($)
{		
	my ($hash) = @_;
	my $name = $hash->{NAME};

	# debug
	Log3 $name, $hash->{logLevel}, 'SPI_CBerry28_Init:';

	if ($hash->{initDone} && $hash->{initDone} == 1) {
		SPI_CBerry28_InitBoard($hash);
		SPI_CBerry28_HardReset($hash);
		SPI_CBerry28_InitTFTcontroller($hash);
		
		SPI_CBerry28_setBacklightPWM($hash, 255);
		
		# Demo Picture...
	}
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
