/*
 
  Kristian's Stargate Project
  Dial Home Device v2.0
  Kristian Tysse & Jonathan Moyes
  TheStargateProject.com
  (c) 2020

  Designed to be run on an ATMEGA32u4, 5v 16MHz
  
  This sketch requires the following Arduino Libraries. All of these can be installed through 
  the Arduino IDE:  Tools->Manage Libraries.

     - Arduino Keyboard ( https://www.arduino.cc/reference/en/language/functions/usb/keyboard/ )
     - CmdMessenger ( https://playground.arduino.cc/Code/CmdMessenger/ )
     - Adafruit's DotStar Library ( https://github.com/adafruit/Adafruit_DotStar )

  As written, this sketch should run without modification on the ATMEGA32u4 and any of the SAMD-bAAAased Arduino-compatible chips.
  Parts of the sketch have been tested on the nRF52840 Feather board (a Cortex-M0 chip), but some modification will be required.

  If you are building the PCBA from scratch, you'll first need to install the Arduino Bootloader on the 32u4.
  You'll want to burn the Catalina Bootloader: https://learn.adafruit.com/introducting-itsy-bitsy-32u4/downloads
  
  ** Some additional hardware is required to burn the bootloader
  Instructions for the process can be found here: https://www.designedbycave.co.uk/2020/ItsyBitsy-Bootloader/

  After burning the bootloader, program this sketch via the Arduino IDE.

*/

// ## VERSION INFO ##############################################

#define FIRMWARE_VERSION_STRING "FW_0.0.5"
#define HARDWARE_VERSION_STRING "HW_0.0.4"
#define IDENTIFIER_STRING       "Kristian's DHD v2"

// ## INCLUDES ##################################################

#include <Adafruit_DotStar.h>
#include "CmdMessenger.h"
#include "Keyboard.h"

// ## CONFIGURATION #############################################

#define UART_BAUD         115200          // USB-Serial Baud Rate. Recommended: 115200.

#define ADC_RESOLUTION        10          // With 9 buttons on a pin, 10-bit is close to a minimum without risk of misinterpreted button presses. The ATMEGA32u4 has a 10-bit.
#define ADC_MAX               1023        // Calculated as `(2^adcbits)-1` (MINUS ONE!!)

const int inputPins[] = { A0, A1, A2, A3, A4 }; // Ensure this is in sequence with buttonMap[]
          
#define NUMBER_OF_PINS    5               // Count of inputPins[] (5)
#define BUTTONS_PER_PIN   9               // How many buttons are attached to each pin?
                                          // Calculate resistor values using this sheet: 
                                          //    https://docs.google.com/spreadsheets/d/1G6wTsAxZDnVvzIDBkg5LrhhY1T7q4p_pDSZ6owvBCMA/edit

#define ENABLE_KEYBOARD_EMULATION   true 
#define ENABLE_SERIAL_DEBUG         false // If you're using cmdMessenger this will cause problems, keep it disabled.

// Buttons 0-39 are mapped to a character we want to send when that button is pressed. Adjust them here.
// The current configuration gives buttons 1-39 as A-Z, then 0-9, then !, @, #...sequentially.
// The buttonMap is read in the order of the inputPins array. If you change the order of those elements, you'll need to re-order them here.
const char fc = "~"; // What character is used to flag unused buttons? Unused buttons are ignored if detected.
const char buttonMap[45] = { // allocation calculated as NUMBER_OF_PINS * BUTTONS_PER_PIN
  'a','b','c', fc, fc, fc, fc, fc, fc,  // Pin A0, Buttons 37-39, plus 6 fillers
  'S','T','U','V','W','X','Y','Z','0',  // Pin A1, Buttons 19-27
  'A','B','C','D','E','F','G','H','I',  // Pin A2, Buttons 1-9
  '1','2','3','4','5','6','7','8','9',  // Pin A3, Buttons 28-36
  'J','K','L','M','N','O','P','Q','R'   // Pin A4, Buttons 10-18
};

// DotStars
#define DOTSTAR_COUNT   39 // How many DotStars are connected? (39)
#define DOTSTAR_DAT     4  // What pin is connected to the DotStar's DI pin (4)
#define DOTSTAR_CLK     12  // What pin is connected to the DotStar's CI pin (12)
Adafruit_DotStar pixels(DOTSTAR_COUNT, DOTSTAR_DAT, DOTSTAR_CLK, DOTSTAR_BGR);

/* Define CmdMessenger commands */
enum {
    get_fw_version,
    get_hw_version,
    get_identifier,
    reset,
    evt_error,
    evt_ack,
    message_bool,
    message_string,
    message_int,
    message_long,
    message_double,
    message_color,
    clear_all,
    clear_pixel,
    set_all,
    set_pixel,
    get_pixel_count,
    set_brightness_symbols,
    set_brightness_center,
    latch
};

// ## SETUP ######################################################

const float avgPerStep = ADC_MAX / float(BUTTONS_PER_PIN);
int lastPress[2];                     // [pin, button]

CmdMessenger c = CmdMessenger(Serial,',',';','/');

// ###############################################################

/* Callback functions to handle incoming commands from Host */

void on_clear_all(void){
    pixels.clear();
}

void on_set_all(void){

  // This command requires three ints
  int red = c.readBinArg<int>();
  int green = c.readBinArg<int>();
  int blue = c.readBinArg<int>();
  
  for(int i=0; i<DOTSTAR_COUNT; i++) { // For each pixel...
    pixels.setPixelColor(i, pixels.Color(red, green, blue));
  }
  
}

void on_set_pixel(void){

  // This command requires four ints
  int pixelIndex = c.readBinArg<int>();
  int red = c.readBinArg<int>();
  int green = c.readBinArg<int>();
  int blue = c.readBinArg<int>();
  
  pixels.setPixelColor(pixelIndex, pixels.Color(red, green, blue));
  
}

void on_clear_pixel(void){

  // This command requires one int
  int pixelIndex = c.readBinArg<int>();
 
  pixels.setPixelColor(pixelIndex, pixels.Color(0, 0, 0));
  
}

void on_get_pixel_count(void){
  int pixelCount = pixels.numPixels();

  c.sendBinCmd(message_int, pixelCount);
  
}

void on_set_brightness_symbols(void){
  
  // This command requires one int
  int brightness = c.readBinArg<int>();
  
  pixels.setBrightness(brightness);
  
}

void on_set_brightness_center(void){
  
  // This command requires one int
  int brightness = c.readBinArg<int>();
  
}

void on_latch(void){
  
  pixels.show();
  
}

// ###############################################################

void on_reset(void){
    //TODO
    //initHardware();
    pixels.clear();
    pixels.show();
    
}

void on_get_fw_version(void){
    c.sendCmd(message_string, FIRMWARE_VERSION_STRING);
}

void on_get_hw_version(void){
    c.sendCmd(message_string, HARDWARE_VERSION_STRING);
}

void on_get_identifier(void){
    c.sendCmd(message_string, IDENTIFIER_STRING);
}

void on_unknown_command(void){
    c.sendCmd(evt_error, "Unknown Command");
}

// ################################

/* Attach callbacks for CmdMessenger commands */
void attach_callbacks(void) { 
  
    c.attach(clear_all, on_clear_all);
    c.attach(clear_pixel, on_clear_pixel);
    c.attach(set_all, on_set_all);
    c.attach(set_pixel, on_set_pixel);
    c.attach(get_pixel_count, on_get_pixel_count);
    c.attach(set_brightness_symbols, on_set_brightness_symbols);
    c.attach(set_brightness_center, on_set_brightness_center);
    c.attach(latch, on_latch);

    c.attach(get_fw_version, on_get_fw_version);
    c.attach(get_hw_version, on_get_hw_version);
    c.attach(get_identifier, on_get_identifier);

    c.attach(reset,on_reset);
    c.attach(on_unknown_command);
}

// ################################

void self_test() {

  pixels.setBrightness(50);
  
  for(int i=0; i<DOTSTAR_COUNT; i++) { // For each pixel...
    pixels.setPixelColor(i, pixels.Color(250, 117, 0));
  }
  pixels.setPixelColor(0, pixels.Color(250, 0, 0));
  on_latch();
  delay(1000);
  
  on_clear_all();
  on_latch();
}

void setup() {
  // Initialize USB/UART/Serial for debugging
  Serial.begin(UART_BAUD);

  // Start our two pixel objects. We'll use `pixels` to clock all 39 pixels, then in a separate object clock only the center pixel.
  // This allows the center button's brightness to be control independently of the symbol buttons.
  pixels.begin();

  // Initialize the array and latch it.
  on_clear_all();
  on_latch();

  self_test();
  
  // Attach our serial command handlers
  attach_callbacks();
  
}

void loop() {

  doKeyboard();
  c.feedinSerialData();
  
}

void initializeKeyboard(void){

  // Initialize last press state
  lastPress[0] = 0;
  lastPress[1] = 0;

  // Initialize the Keyboard/HID Emulation library
  Keyboard.begin();
  
}

void doKeyboard(void){
  bool hasPress = false;
  
  for (byte pin = 0; pin < NUMBER_OF_PINS; pin++) {
    int button = getButtonPressedByPin(inputPins[pin]);
    delay(1);
    int button2 = getButtonPressedByPin(inputPins[pin]);

    if ( button != button2 ){
      continue;
    }
    
    // Is a button pressed?
    if ( button > 0 ){
      // Yes!
      hasPress = true;
      
      // Debounce - only act once if the button is held 
      if ( pin != lastPress[0] || button != lastPress[1] ){
        
        // Calculate this button's index, use it to lookup the character to send
        int buttonMapIndex = ( pin * BUTTONS_PER_PIN ) + button-1;

        // If we detect unused buttons, ignore them.
        if ( buttonMap[buttonMapIndex] == fc ){
          continue;
        }
        
        // Debug output
        if( ENABLE_SERIAL_DEBUG ){
          Serial.print("Pressed: Pin ");
          Serial.print(pin);
          Serial.print(" Button: ");
          Serial.print(button);
          Serial.print(" Index: ");
          Serial.print(buttonMapIndex);
          Serial.print(" Char: ");
          Serial.println(buttonMap[buttonMapIndex]);
        }

        // Send the keyboard character
        if( ENABLE_KEYBOARD_EMULATION ){
          Keyboard.print(buttonMap[buttonMapIndex]);
        }
        
        // Store the last pressed pin/button signature so we can debounce/suppress when being held.
        lastPress[0] = pin;
        lastPress[1] = button;
        
      }
    }
  }

  // If we went all the way around all of the pins and didn't see any 
  // buttons pressed, clear the lastPress to allow a new button to be pressed
  if (!hasPress){
    lastPress[0] = 0;
    lastPress[1] = 0;
  }

  
}

int getButtonPressedByPin( int pin ) {
  
  delay(1); // Some time to let the Pin settle
  int adc = analogRead(pin); // Sample and it throw out - second reading is more stable.
  adc = analogRead(pin); 
  
  if (adc > (BUTTONS_PER_PIN - 0.5) * avgPerStep) { 
    return 0; 
  }

  for (int button = 0; button < BUTTONS_PER_PIN; button++) {
    if (adc < round((button + 0.5) * avgPerStep)) { 
      return button + 1; 
    }
  }

  return 0;
}
