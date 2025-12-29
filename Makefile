SDK = $(HOME)/Developer/PlaydateSDK
PDC = $(SDK)/bin/pdc
SIM = open -a "Playdate Simulator"

PRODUCT = Spotify.pdx
SOURCE = src

.PHONY: build run clean

build:
	$(PDC) -k -v $(SOURCE) $(PRODUCT)

run: build
	$(SIM) $(PRODUCT)

clean:
	rm -rf $(PRODUCT)
