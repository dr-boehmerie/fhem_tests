use strict;
use warnings;

use Device::BCM2835;

use Time::HiRes qw(usleep);

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

##################################################
# Forward declarations
#
sub SPI_CBerry28_InitController($);


# write byte to register
sub SPI_CBerry28_WriteReg($$)
{
	my ($hash, $val) = @_;

#	my @temp = ($val);

	eval {
		Device::BCM2835::gpio_write($hash->{pinRS}, 0);

		print "SPI_CBerry28_WriteReg: $val\n";
		
	#	my $resp = Device::BCM2835::spi_transfer( pack('C1', @temp) );
	#	my $resp = Device::BCM2835::spi_transfer( pack ('H*', $val) );
		my $resp = Device::BCM2835::spi_transfer( $val );

	} or do {
		my $e = $@;
		print "SPI_CBerry28_WriteReg: exception $e\n";
	};
}

# write byte to tft
sub SPI_CBerry28_WriteData($$)
{
	my ($hash, $val) = @_;

#	my @temp = ($val);

	eval {
		Device::BCM2835::gpio_write($hash->{pinRS}, 1);
	
		print "SPI_CBerry28_WriteData: $val\n";
		
	#	my $resp = Device::BCM2835::spi_transfer( pack('C1', @temp) );
	#	my $resp = Device::BCM2835::spi_transfer( pack ('H*', $val) );
		my $resp = Device::BCM2835::spi_transfer( $val );
		
	} or do {
		my $e = $@;
		print "SPI_CBerry28_WriteData: exception $e\n";
	};
}

# write 3 * 'count'-bytes to tft
sub SPI_CBerry28_WriteMultiData($$@)
{
	my ($hash, $cnt, @vals) = @_;

	eval {
		Device::BCM2835::gpio_write($hash->{pinRS}, 1);

		my $data = pack ('C*', @vals);
		
		print "SPI_CBerry28_WriteMultiData: $cnt; @vals\n";
		
		# $cnt
	#	my $resp = Device::BCM2835::spi_transfer( pack('C' . $cnt, @a) );
	#	my $resp = Device::BCM2835::spi_transfer( pack('H*', $vals) );
	#	my $resp = Device::BCM2835::spi_transfer( @vals );
		Device::BCM2835::spi_transfern( $data );
		
	} or do {
		my $e = $@;
		print "SPI_CBerry28_WriteMultiData: exception $e\n";
	};
}

# write command to a register
sub SPI_CBerry28_SetRegister($$$@)
{
	my ($hash, $reg, $cnt, @vals) = @_;
#	my $reg = $a[0];
#	my $cnt = $a[1];
#	my $i;

	print "SPI_CBerry28_SetRegister: $reg; $cnt; @vals\n";

	SPI_CBerry28_WriteReg ($hash, $reg);

#	for (i = 0; i < $cnt; i++) {
#		SPI_CBerry28_WriteData ($hash, $a[i]);
#	}
	SPI_CBerry28_WriteMultiData ($hash, $cnt, @vals);
}

# define area of frame memory where MCU can access
sub SPI_CBerry28_SetRow($$$)
{
	my ($hash, $row_start, $row_end) = @_;

	SPI_CBerry28_SetRegister ($hash,
		RASET, 4,
		(($row_start >> 8) & 0xFF, $row_start & 0xFF,
		($row_end >> 8) & 0xFF, $row_end & 0xFF));
}

sub SPI_CBerry28_SetColumn($$$)
{
	my ($hash, $col_start, $col_end) = @_;

	SPI_CBerry28_SetRegister ($hash,
		CASET, 4,
		(($col_start >> 8) & 0xFF, $col_start & 0xFF,
		($col_end >> 8) & 0xFF, $col_end & 0xFF));
}

# initialization of ST7789
sub SPI_CBerry28_InitTFTcontroller($)
{
	my ($hash) = @_;

	# *************** wakeup display
	SPI_CBerry28_WriteReg($hash, SLPOUT);
	usleep(120 * 1000);

	# *************** display and color format setting

	# write data from top-left to bottom-right
	SPI_CBerry28_SetRegister($hash, MADCTL, 1, (0xA0));	# 0x00

	if (CM_262K == 1) {
		# 18bit/pixel
		# 262K-colors (RGB 6-6-6)
		SPI_CBerry28_SetRegister($hash, COLMOD, 1, (0x06));
	} else {
		# 16bit/pixel
		# 65K-colors (RGB 5-6-5)
		SPI_CBerry28_SetRegister($hash, COLMOD, 1, (0x05));
	}

	# *************** ST7789 porch setting

	# seperate porch control = disabled
	# front porch in normal mode  = 13 CLK pulse
	# back porch in normal mode   = 13 CLK pulse
	# front porch in idle mode    =  3 CLK pulse
	# back porch in idle mode     =  3 CLK pulse
	# front porch in partial mode =  3 CLK pulse
	# back porch in partial mode  =  3 CLK pulse
	SPI_CBerry28_SetRegister($hash, PORCTRL, 5, (0x0C, 0x0C, 0x00, 0x33, 0x33));

	# *************** ST7789 Power setting

	# VGH =  12.26V
	# VGL = -10.43V
	SPI_CBerry28_SetRegister($hash, GCTRL, 1, (0x35));

	# VDV and VRH register value comes from command line
	SPI_CBerry28_SetRegister($hash, VDVVRHEN, 1, (0x1F));

	# VAP = 4.7 + Vcom + Vcom_offset + 0.5*VDV
	SPI_CBerry28_SetRegister($hash, VRHS, 1, (0x2C));

	# VDV = 0V
	SPI_CBerry28_SetRegister($hash, VDVSET, 1, (0x01));

	# Vcom = 0.875V
	SPI_CBerry28_SetRegister($hash, VCOMS, 1, (0x17));

	# Vcom_offset = 0V
	SPI_CBerry28_SetRegister($hash, VCMOFSET, 1, (0x20));

	# AVDD =  6.6V
	# AVCL = -4.8V
	# VDS  =  2.3V
	SPI_CBerry28_SetRegister($hash, PWCTRL1, 2, (0xA4, 0xA1));

	# *************** ST7789 gamma setting

	SPI_CBerry28_SetRegister($hash, PVGAMCTRL, 14, (0xD0, 0x00, 0x14, 0x15, 0x13, 0x2C, 0x42, 0x43, 0x4E, 0x09, 0x16, 0x14, 0x18, 0x21));
	SPI_CBerry28_SetRegister($hash, NVGAMCTRL, 14, (0xD0, 0x00, 0x14, 0x15, 0x13, 0x0B, 0x43, 0x55, 0x53, 0x0C, 0x17, 0x14, 0x23, 0x20));

	# *************** miscellaneous settings

	# define area (start row, end row, start column, end column) of frame memory where MCU can access
	SPI_CBerry28_SetRow($hash, 0, DISPLAY_HEIGHT - 1 );
	SPI_CBerry28_SetColumn($hash, 0, DISPLAY_WIDTH - 1 );

	# *************** display on
	SPI_CBerry28_WriteReg($hash, DISPON);
}

# initialization of GPIO and SPI
sub SPI_CBerry28_InitBoard ($)
{
	my ($hash) = @_;

	# *************** set the pins to be an output and turn them on
	eval {
	#	Device::BCM2835::set_debug(1);
		
		my $ret = Device::BCM2835::init();
		if ($ret == 1) {
			# Init SPI
			Device::BCM2835::spi_begin();
			Device::BCM2835::spi_setBitOrder(Device::BCM2835::BCM2835_SPI_BIT_ORDER_MSBFIRST);		# The default
			Device::BCM2835::spi_setDataMode(Device::BCM2835::BCM2835_SPI_MODE0);					# The default
			Device::BCM2835::spi_setClockDivider(Device::BCM2835::BCM2835_SPI_CLOCK_DIVIDER_4096);	# 61kHz
		#	Device::BCM2835::spi_setClockDivider(Device::BCM2835::BCM2835_SPI_CLOCK_DIVIDER_512);	# 488kHz
		#	Device::BCM2835::spi_setClockDivider(Device::BCM2835::BCM2835_SPI_CLOCK_DIVIDER_128);	# 1.9MHz
			Device::BCM2835::spi_chipSelect(Device::BCM2835::BCM2835_SPI_CS0);						# The default
			Device::BCM2835::spi_setChipSelectPolarity(Device::BCM2835::BCM2835_SPI_CS0, 0);		# the default

			# Control Pins using BCM2835
			# RST = 22
			$hash->{pinRST} = &Device::BCM2835::RPI_GPIO_P1_22;
			Device::BCM2835::gpio_fsel($hash->{pinRST}, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
			Device::BCM2835::gpio_write($hash->{pinRST}, 0);
			# RS = 15
			$hash->{pinRS} = &Device::BCM2835::RPI_GPIO_P1_15;
			Device::BCM2835::gpio_fsel($hash->{pinRS}, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
			Device::BCM2835::gpio_write($hash->{pinRS}, 0);
			# PWM = 12
			$hash->{pinPWM} = &Device::BCM2835::RPI_GPIO_P1_12;
			Device::BCM2835::gpio_fsel($hash->{pinPWM}, &Device::BCM2835::BCM2835_GPIO_FSEL_OUTP);
			Device::BCM2835::gpio_write($hash->{pinPWM}, 0);
			
	# Clock divider is set to 16.
	# 1.2MHz/1024 = 1171.875Hz
#	bcm2835_pwm_set_clock(BCM2835_PWM_CLOCK_DIVIDER_16);
#	bcm2835_pwm_set_mode(PWM_CHANNEL, 1, 1);
#	bcm2835_pwm_set_range(PWM_CHANNEL, PWM_RANGE);
			
			$hash->{initDone} = 1;
		}
	} or do {
		my $e = $@;
	};
}


# hard reset of the tft controller
sub SPI_CBerry28_HardReset($)
{
	my ($hash) = @_;

	usleep(1 * 1000);
	Device::BCM2835::gpio_write($hash->{pinRST}, 0);
	usleep(10 * 1000);
	Device::BCM2835::gpio_write($hash->{pinRST}, 1);
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

	if ($hash->{initDone} && $hash->{initDone} == 1) {
	#	bcm2835_pwm_set_data( PWM_CHANNEL, BL_value );
		# TODO: PWM value
		if ($val > 0) {
			Device::BCM2835::gpio_write($hash->{pinPWM}, 1);
		} else {
			Device::BCM2835::gpio_write($hash->{pinPWM}, 0);
		}
	#	HiPi::Wiring::pwmWrite(BL_PWM, $val)
	}
}

sub SPI_CBerry28_InitController($)
{		
	my ($hash) = @_;
	
	$hash->{initDone} = 0;
	
	SPI_CBerry28_InitBoard($hash);
	
	if ($hash->{initDone} == 1) {
		# Initialize Display
		SPI_CBerry28_HardReset($hash);
		SPI_CBerry28_InitTFTcontroller($hash);
		
		SPI_CBerry28_setBacklightPWM($hash, 255);
		
		# Clear Display
	#	SPI_CBerry28_Clear($hash);
	
		# Demo picture

		
		Device::BCM2835::spi_end();

	} else {
		return "Error! Hardware setup failed!";
	}
}


my $CBerry = ();

SPI_CBerry28_InitController($CBerry);
