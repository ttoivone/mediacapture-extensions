DOC := face-detection-explainer.md
DEST := face-detection-explainer.html

.PHONY: all clean
all: $(DEST)

clean:
	rm -f $(DEST)

%.html: %.md
	pandoc --number-sections --reference-links --reference-location=document -o $@ -f markdown -t html5 $<
