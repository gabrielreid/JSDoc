/*
 * This file is to be used for testing the JSDoc parser
 * It is not intended to be an example of good JavaScript OO-programming,
 * nor is it intended to fulfill any specific purpose apart from 
 * demonstrating the functionality of the parser
 */

/*******************************************************************
 *************        Big Block Comment ****************************
 *******************************************************************/

/**
 * This is the basic Shape class.  
 * It can be considered an abstract class, even though no such thing
 * really existing in JavaScript
 * TODO: This is an example todo message
 * @constructor
 */
function Shape(){
  
   /**
    * This is an example of a function that is not given as a property
    * of a prototype, but instead it is assigned within a constructor.
    * For inner functions like this to be picked up by the parser, the
    * function that acts as a constructor <b>must</b> be denoted with
    * the <b>&#64;constructor</b> tag in its comment.
    */
   this.innerFunction = function(){
      return "Shape";
   }

   /** This is another inner */
   this.anotherInner = function(){
   }
   
   /** This is a private method, just used here as an example */
   function privateFunction(){
      return 'Private';
   }
   
}


/**
 * This is an unattached function 
 * @param One one
 * @param Two two
 */
function UnattachedFunction(One, Two){
   return "";
}


/**
 * The color of this shape
 */
Shape.prototype.color = null;

/**
 * The border of this shape. 
 */
Shape.prototype.border = null;

/* 
 * The assignment of function implementation for Shape 
 */

Shape.prototype.getCoords = Shape_GetCoords;

Shape.prototype.getColor = Shape_GetColor;

Shape.prototype.setCoords = Shape_SetCoords;

Shape.prototype.setColor = Shape_SetColor;

/*
 * These are all the instance method implementations for Shape
 */

/**
 * Get the coordinates of this shape. It is assumed that we're always talking
 * about shapes in a 2D location here.
 *
 * @returns A Coordinate object representing the location of this Shape
 */
function Shape_GetCoords(){
   return this.coords;
}

/**
 * Get the color of this shape
 * @see #setColor
 */
function Shape_GetColor(){
   return this.color;
}

/**
 * Set the coordinates for this Shape
 * @argument coordinates The coordinates to set for this Shape
 */
function Shape_SetCoords(coordinates){
   this.coords = coordinates;
}

/**
 * Set the color for this Shape
 * @param color The color to set for this Shape
 * @param other There is no other param
 * @throws NonExistantColorException (no, not really!)
 */
function Shape_SetColor(color){
   this.color = color;
}


/**
 * A basic rectangle class, inherits from Shape.
 * This class could be considered a concrete implementation class
 * @param width The optional width for this Rectangle
 * @param height Thie optional height for this Rectangle
 */
function Rectangle(width, height){
   if (width){
      this.width = width;
      if (height){
	 this.height = height;
      }
   }
}

/* Inherit from Shape */
Rectangle.prototype = new Shape();

/**
 * Value to represent the width of the Rectangle
 */
Rectangle.prototype.width = 0;

/**
 * Value to represent the height of the Rectangle
 */
Rectangle.prototype.height = 0;

/**
 * This is just an anonymous function for testing
 */
Rectangle.prototype.rectFunction = function(){
   return 0;
}

/*
 * These are all the instance method implementations for Rectangle 
 */

Rectangle.prototype.getWidth = Rectangle_GetWidth;

Rectangle.prototype.getHeight = Rectangle_GetHeight;

Rectangle.prototype.setWidth = Rectangle_SetWidth;

Rectangle.prototype.setHeight = Rectangle_SetHeight;

Rectangle.prototype.getArea = Rectangle_GetArea;


/**
 * Get the value of the width for the Rectangle
 */
function Rectangle_GetWidth(){
   return this.width;
}

/**
 * Get the value of the height for the Rectangle
 */
function Rectangle_GetHeight(){
}

/**
 * Set the width value for this Rectangle
 * @param width The width value to be set
 */
function Rectangle_SetWidth(width){
   this.width = width;
}

/**
 * Set the height value for this Rectangle
 * @param height The height value to be set
 */
function Rectangle_SetHeight(height){
   this.height = height;
}

/**
 * Get the value for the total area of
 * this Rectangle
 */
function Rectangle_GetArea(){
   return width * height;
}


/**
 * A Square is a subclass of {@link Rectangle}
 * @param width The optional width for this Rectangle
 * @param height The optional height for this Rectangle
 */
function Square(width, height){
   if (width){
      this.width = width;
      if (height){
	 this.height = height;
      }
   } 
   
}

/* Square is a subclass of Rectangle */
Square.prototype = new Rectangle();


/* 
 * The assignment of function implementation for Shape 
 */

Square.prototype.setWidth = Square_SetWidth;

Square.prototype.setHeight = Square_SetHeight;



/**
 * Set the width value for this Square.
 * @param width The width value to be set
 */
function Square_SetWidth(width){
   this.width = this.height = width;
}

/**
 * Set the height value for this Square 
 * @param height The height value to be set
 */
function Square_SetHeight(height){
   this.height = this.width = height;
}


/**
 * Circle class is another subclass of Shape
 * @param radius The optional radius of this Circle
 */
function Circle(radius){
   if (radius){
      this.radius = radius;
   }
}

/* Circle inherits from Shape */
Circle.prototype = new Shape();

/** The radius value for this Circle */
Circle.prototype.radius = 0;

/** 
 * A very simple class (static) field 
 */
Circle.PI = 3.14;

Circle.getClassName = Circle_GetClassName;

Circle.prototype.getRadius = Circle_GetRadius;

Circle.prototype.setRadius = Circle_SetRadius;

/**
 * Get the radius value for this Circle
 */
function Circle_GetRadius(){
   return this.radius;
}

/** 
 * Set the radius value for this Circle
 * @param radius The radius value to set
 */
function Circle_SetRadius(radius){
   this.radius = radius;
}

/** 
 * A class (static) method.
 * @param test This is a test param
 */
function Circle_GetClassName(test){
   return "Circle";
}


/**
 * Coordinate is a class that can encapsulate location information
 * @param x The optional x portion of the Coordinate
 * @param y The optinal y portion of the Coordinate
 */
function Coordinate(x, y){
   if (x){
      this.x = x;
      if (y){
	 this.y = y;
      }
   }
}

/** The x portion of the Coordinate */
Coordinate.prototype.x = 0;

/** The y portion of the Coordinate */
Coordinate.prototype.y = 0;

Coordinate.prototype.getX = Coordinate_GetX;
Coordinate.prototype.getY = Coordinate_GetY;
Coordinate.prototype.setX = Coordinate_SetX;
Coordinate.prototype.setY = Coordinate_SetY;

/**
 * Get the x portion of the Coordinate 
 */
function Coordinate_GetX(){
   return this.x;
}

/** 
 * Get the y portion of the Coordinate
 */
function Coordinate_GetY(){
   return this.y;
}

/**
 * Set the x portion of the Coordinate
 * @param x The x value to set
 */
function Coordinate_SetX(x){
   this.x = x;
}

/** 
 * Set the y portion of the Coordinate
 * @param y The y value to set
 */
function Coordinate_SetY(y){
   this.y = y;
}
