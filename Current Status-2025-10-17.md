# Current Status - 2025-10-17

## The Python scripts did a better job:

1. `Conversion-Tools.md`				- 	Documentation. May need updating

2. `aar_to_mif_converter.Python`		- 	Very good. The one I used to finally
											convert Thai arr to MIF. This confirms that our ttx_to_fea.py did a good job in generating the aar correctly. Also the aar's contextual substitution rules (before, between and after) works.

3. `font_compare.py` 					-	Very good. I used this to compare layout 
											of ot and aat fonts against 17k thai words. Takes long. Can pass maxerror, tollerance (I passed 3.0) in the command line.
```bash
font_compare.py NotoSansThai-Regular_256-OT.ttf NotoSansThai-Regular_256-AAT.ttf th-words-few.txt --shaper coretext --tolerance 3.0
```

4. gpos_to_kerx_converter.py 			- 	Specifically converted gpos fea generated 
											from OTM to kerx. Can use this as reference to verify the swift version. May not have handled all conversion types, like mark to ligature.

5. gpos_to_kerx_converter_guide.md 		-	Doc for the above

6. gposaar2kerxatif.py 					-	Converts aar positioning rules to atif

```bash
gposaar2kerxatif.py thai_marks.aar thai_marks_fixed.atif
```

7. gposfea2kerxaar.py 						- 	Converts fea to aar so it can be used 
											as input to the above
```bash
gposfea2kerxaar.py thai_marks.fea thai_marks.aar
```

8. gsubfea2morxaar.py 						- 	Converts gsub fea to aar. Very good.

9. gsubfea2morxaar.readme.md 				- 	Doc for the above.

10. ttx_to_fea.py 							- 	Extremely useful. Converts ttx GSUB table 
											output from xml to fea syntax.

## Next steps:

1. Use the scripts as reference to improve the swift implementation. Swift covers more table types to be comprehensive

2. Alternatively, build the entire conversion in python - may not be useable in our apps later on!



