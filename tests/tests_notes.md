Setup: root is Row, available space is 200 × 100. A and B are its children, each with Grow := 1.0 and everything else default.

Row means the main axis is horizontal, so width is the main size and height is the cross size.
Root fills the available space: (0, 0, 200, 100).
Free space on the main axis = 200 − 0 = 200. A and B have no declared width or content, so their base size is 0.
Each grower gets 200 × 1/2 = 100. It divides evenly, so no remainder step is needed.
A starts at x = 0. B starts where A ends, at x = 100.
The default cross alignment is Stretch, so both fill the full height of 100 at y = 0.

Results:
Node	X	Y	Width	Height
A	   0	0	100	100
B	  100 0	100	100

## Make
  Make is an expression function, so it has no begin...end surronding the function.
  Make returns a record aggregate with name associations. The X and Y are set as Coord. Coord means that they are a position that can hold a positive or negative value. Width and Height are set to Length. They can not be a negative value. 
  Seen in: Check ("A is left half",  Layout_Of (T, A) = Make (0.0,   0.0, 100.0, 100.0));

## Record =
  Rect is a record that holds Point and Size. The package does not have a defined "=", so Ada has a default method to define how two rects should be compared.
  Two rects are only equal if the X,Y and Width,Height values of both rects are equal to eachother.

## Overlaps
   Overlaps if the function to check if the rects are overlapping eachother. If "A.Origin.X < Right (B)" is true, then the function runs 4 different checks if any edges are overlapping. 
   The compaisions use <, so if edges are touching, they are not considered as overlapping. If A is at 0 to 100 and B is at 100 to 200, this won't count as overlap.

## Contains
   Contains is a similar function to Overlaps, excpet Contains is checking if a rect is inside or outside the parent rect; meanwhile, Overlaps is checking if they are sharing the same area.
   Contains uses <=, so if any edges are touching, it will count as the rect being inside of the other.

 