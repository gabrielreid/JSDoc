package JSDoc;

=head1 NAME

JSDoc - parse JavaScript source file for JSDoc comments

=head1 SYNOPSIS

Create JavaScript sourcefiles commented in a manner similar to javadoc
(ie. with documentation starting with '/**' and then pass a list of references 
to JavaScript source to parse_code_tree:

   /**
    * This is a class for example purposes
    * @param name Name for the new object
    * @constructor
    */
    function MyClass(name){
      this.name = name;
    }

   $code_tree = parse_code_tree(@src_refs);

A tree structure describing the code layout, inheritance and documentation
is returned

To clear the cache of classes and functions in the parser:

   reset_parser();
    

=head1 DESCRIPTION

The C<parse_code_tree> function requires a ref to a string holding the
souce code of a javascript object file or files. It returns a data structure
that describes the object hierarchy contained in the source file, as well
as included documentation for all fields and methods. The resulting
data structure has the following form (for each class):

   Class
      |
      +- constructor_args
      |
      +- extends  
      |
      +- constructor_summary
      |
      +- constructor_vars
      |
      +- class_methods
      |  |
      |  +- description
      |  |
      |  +- mapped_name
      |  |
      |  +- argument_list
      |  |
      |  +- vars 
      |
      +- instance_methods
      |  |
      |  +- description
      |  |
      |  +- mapped_name
      |  |
      |  +- argument_list
      |  |
      |  +- vars 
      | 
      +- class_fields
      |  |
      |  +- field_description
      |  |
      |  +- field_name
      |  |
      |  +- field_vars
      |
      +- instance_fields
      |  |
      |  +- field_description
      |  |
      |  +- field_name
      |  |
      |  +- field_vars
      |
      +- inner_classes
      |  |
      |  +- class_name
      |
      +- inherits
         |
         +- Class
            |
            +- instance_fields
            |
            +- instance_methods

=head1 AUTHOR

Gabriel Reid gab_reid@users.sourceforge.net,
Michael Mathews michael@mathews.net

=cut

require 5.000;
use strict;
use warnings;
use Exporter;
use Data::Dumper;

use vars qw/ @ISA @EXPORT /;

@ISA = qw(Exporter);
@EXPORT = qw(parse_code_tree configure_parser reset_parser);

# State
use vars qw/ %CLASSES %FUNCTIONS %CONFIG $CTX_FILE /;

# Regexes
use vars qw/ $BAL_PAREN $BAL_BRACE $SQUOTE $DQUOTE $NONQUOTE 
               $FUNC_DEF $ANON_FUNCTION $LITERAL $FUNC_CALL $JSDOC_COMMENT 
               $MLINE_COMMENT $SLINE_COMMENT /;

$BAL_PAREN = qr/\((?:[^()]|(??{$BAL_PAREN}))*\)/;
$BAL_BRACE = qr/\{(?:[^{}]|(??{$BAL_BRACE}))*\}/;
$SQUOTE = qr{'[^'\\]*(?:\\.[^'\\]*)*'};
$DQUOTE = qr{"[^"\\]*(?:\\.[^"\\]*)*"};
$NONQUOTE = qr{[^"'/]};
$FUNC_DEF = qr/function\s+\w+(?:\.\w+)*\s*$BAL_PAREN\s*$BAL_BRACE/;
$ANON_FUNCTION = qr/function\s*$BAL_PAREN\s*$BAL_BRACE/;
$LITERAL = qr/$DQUOTE|$SQUOTE|\d+/;
$FUNC_CALL = qr/(?:new\s+)?\w+(?:\.\w+)*\s*$BAL_PAREN/;
$JSDOC_COMMENT = qr{/\*\*[^*]*\*+(?:[^/*][^*]*\*+)*/};
$MLINE_COMMENT = qr{/\*[^*]*\*+(?:[^/*][^*]*\*+)*/};
$SLINE_COMMENT = qr{//[^\n]*};


#
# Public function that returns a datastructure representing the JS classes
# and their documentation
#
sub parse_code_tree {

   #
   # This (I mean the "<<$_>>") is pretty hacky, but I've made it this 
   # way to maintain backwards compatibility with anyone who's automatically 
   # expecting this to work when they throw an array of refs to it. If you're
   # using this for your own work, please don't expect to be able to 
   # put the context file in like this in the future
   #
   for my $js_src (map { ref and ${$_} or "<<$_>>" } @_){

      if ($js_src =~ /^<<(.+)>>$/){
         $CTX_FILE = $1;
         next;
      }

      # perlify os line-endings
      $js_src =~ s/(\r\n|\r)/\n/g;

      $js_src = &preprocess_source($js_src);
      &fetch_funcs_and_classes($js_src);
   }
   
   &map_all_properties();

   &build_class_hierarchy(); 
   
   &set_class_constructors();

   for my $class(values %CLASSES){
      delete $class->{_class_properties};
      delete $class->{_instance_properties};
   }
   return \%CLASSES;
}

#
# Parses up a a jsdoc comment into its component parts
# PARAM: The document string to be parsed
#
sub parse_jsdoc_comment {
   my $doc = shift;

   $doc =~ s/^\s*\*//gm;

   # remember each part that is parsed
   my %parsed = ();

   # the first paragraph could be a summary statement
   # a paragraph may follow of variable defs (variable names start with "@")
   my ($summary, $variable_str) = $doc =~ 
                     /^\s*
                     (
                        (?:[^{@]|(?:\{[^@]))*
                        (?:\{\@
                           (?:[^{@]|(?:\{[^@]))*
                        )*)
                     \s*
                     (.*)
                     $/xs;

   $parsed{summary} = $summary;


   # two types of variable def can be dealt with here:
   # a @argument has a two-part value -- the arg name and a description
   # all other @<variables> only have a single value each (although there may
   # be many variables with the same name)
   if($variable_str) {
       my %vars = ();
       while ($variable_str =~ /
          (?<!\{)\@(\w+)      # The @attribute, but not a {@link}
          \s*
          ((?:\{\@|[^\@])*)            # Everything up to the next @attribute
          /gsx) {
           my ($name, $val) = ($1, $2);
           $vars{$name} = [] unless defined $vars{$name};
           $val =~ s/\n/ /g;
           push(@{$vars{$name}}, ($val =~ /^\s*(.*)\s*$/)[0]);
       }
       $parsed{vars} = \%vars;
   }
   return \%parsed;
}

#
# Builds up the global FUNCTION and CLASSES hashes
# with the names of functions and classes
#
sub fetch_funcs_and_classes {
   my $js_src = shift;
   
   while ($js_src =~ m!
         # Documentation
         (?:
            /\*\*                         # Opening of docs
               ([^/]+
                  (?:(?:[^*]/)+[^/]+)*
               )
            \*/\s*\n\s*                   # Closing of docs
         )?
         
         # Function
         (?:(?:function\s+(\w+)\s*(\(.*?\))\s*\{)|         
         
         # Anonymous function
         (?:(\w+(?:\.\w+)*?)(\.prototype)?\.(\w+)\s*=\s*function\s*(\(.*?\)))|  

         # Instance property 
         (?:(\w+(?:\.\w+)*?)\.prototype\.(\$?\w+)\s*=\s*(.*?)\s*[;\n])|    

         #Inheritance
         (?:(\w+(?:\.\w+)*?)\.prototype\s*=
                           \s*new\s*(\w+(?:\.\w+)*?)\(.*?\)\s*[;\n])| 

         # Class property
         (?:(\w+(?:\.\w+)*?)\.(\$?\w+)\s*=\s*(.*?)\s*[;\n]))        
      !gsx){
    
      my $doc;
      $doc = $1 or $doc = "";


      if ($2){
         my ($func, $arglist, $post) = ($2, $3, $');
         &add_function($doc, $func, $arglist);
         if ($doc =~ /\@constructor/){
            # Add all @constructor methods as classes
            &add_class($func);
         }
      } elsif ($4 && $6 && $FUNCTIONS{$4}){
         # Anonymous functions added onto a class or class prototype
         &add_anonymous_function($doc, $4, $6, $7, not defined($5));
      } elsif ($4 && $6 && not defined($FUNCTIONS{$4})){
         # Called for methods added to the prototype of core classes
         &add_anonymous_function($doc, $4, $6, $7, not defined($5));
      } elsif ($8 && $9 && defined($10)) {
         &add_property($doc, $8, $9, $10, 0);
      } elsif ($11 && $12){
         &set_base_class($11, $12);
      } elsif ($13 && $14 && defined($15) && $14 ne 'prototype' 
         && $13 ne 'this' && ($FUNCTIONS{$13} or $CLASSES{$13})){
            &add_property($doc, $13, $14, $15, 1);
      }
   }
}

#
# Add a function that is given as Class.prototype.blah = function(){...}
#
sub add_anonymous_function {
   my ($doc, $class, $function_name, $arg_list, $is_class_prop) = @_;
   &add_class($class);
   my $fake_name = "__$class.$function_name";
   
   # This is dirty
   my $is_private = $function_name =~ s/^__________// || $doc =~ /\@private/;

   &add_function($doc, $fake_name, $arg_list, $is_private) and
      &add_property(
         $doc, $class, $function_name, $fake_name, $is_class_prop);
   &add_class("$class.$function_name") if $doc =~ /\@constructor/;

}


# 
# Add a class to the global CLASSES hash
#
sub add_class {
   my $class = shift;
   if (!$CLASSES{$class}){
      $CLASSES{$class} = {};
      $CLASSES{$class}->{instance_fields} = [];
      $CLASSES{$class}->{class_fields} = [];
      $CLASSES{$class}->{instance_methods} = [];
      $CLASSES{$class}->{class_methods} = [];
      $CLASSES{$class}->{inner_classes} = [];
   }
}

#
# Set the base class for a given class
#
sub set_base_class {
   my ($class, $base_class) = @_;
   &add_class($class);
   $CLASSES{$class}->{extends} = $base_class;
}

#
# Add a property, either a class or instance method or field
#
sub add_property {
   my ($doc, $class, $property, $value, $is_class_property) = @_;
   &add_class($class);
   my $parsed_doc = &parse_jsdoc_comment($doc);
   $doc = $parsed_doc->{summary};
   my $key = $is_class_property ? '_class_properties' : '_instance_properties';
   for my $classref (@{$CLASSES{$class}->{$key}}){
      if ($classref->{property_name} eq $property){
         warn "Already bound property '$property' to '$class'\n";
         return;
      }
   }

   push @{$CLASSES{$class}->{$key}}, 
      {
	 property_doc => $doc,
	 property_name => $property,
	 property_value => $value,
         property_vars => $parsed_doc->{vars} 
      };
}


#
# Add a function and its documentation to the global FUNCTION hash
#
sub add_function {
   my ($doc, $function, $arg_list, $is_private) = @_;

   # clean remaining comments out of arg list
   # (all others are already gone)
   # Again, taken from Jeffrey Friedl's "Mastering Regular Expressions"
   {
      no warnings;
      $arg_list =~ s/
         ($NONQUOTE+|
            $DQUOTE$NONQUOTE*|
            $SQUOTE$NONQUOTE*)
         |$MLINE_COMMENT|$SLINE_COMMENT/$1/gx;
   }

   if ($FUNCTIONS{$function}){
      warn "Function $function already declared\n";
      return 0;
   }
   $FUNCTIONS{$function} = {};
   my $func = $FUNCTIONS{$function};
   $arg_list and $func->{argument_list} = join(" ", split("\\s+", $arg_list))
      or $func->{argument_list} = "()";
    
   my $documentation = parse_jsdoc_comment($doc);
   my $function_ref = $FUNCTIONS{$function};
   
   $function_ref->{documentation} = $documentation;
   $function_ref->{description} = $documentation->{summary};

   $function_ref->{vars} = $function_ref->{documentation}->{vars};
   $function_ref->{vars}->{filename} = $CTX_FILE;
   $function_ref->{vars}->{private} = 1 if $is_private;
   1;
}


#
# Map all the class and instance properties to their implementation
#
sub map_all_properties {
   for my $class (keys %CLASSES){
      for my $class_property (@{$CLASSES{$class}->{_class_properties}}){
         my $description = $class_property->{property_doc};
         my $prop_name = $class_property->{property_name};
         my $prop_val = $class_property->{property_value};
         my $prop_vars = $class_property->{property_vars};
         &map_single_property(
            $class, $prop_name, $prop_val, $description, $prop_vars, 1);
      }
   }

   for my $class (keys %CLASSES){
      for my $instance_property (@{$CLASSES{$class}->{_instance_properties}}){
         my $description = $instance_property->{property_doc};
         my $prop_name = $instance_property->{property_name};
         my $prop_val = $instance_property->{property_value};
         my $prop_vars = $instance_property->{property_vars};
         &map_single_property (
            $class, $prop_name, $prop_val, $description, $prop_vars, 0);
      }
   }

   # Map all the unattached functions
   my $classname = $CONFIG{GLOBALS_NAME} || 'GLOBALS';
   &add_class($classname);
   for my $function (grep !($FUNCTIONS{$_}->{is_mapped} || $CLASSES{$_}), 
      keys %FUNCTIONS){
         &map_single_property($classname, $function, $function, '', undef, 1);
   }

   # Map static inner classes
   for $classname (keys %CLASSES){
      my $i = 0;
      my @to_remove;
      for my $cprop (@{$CLASSES{$classname}->{class_methods}}){
         my $propname = $cprop->{mapped_name};
         if ($CLASSES{"$classname.$propname"}){
            push @to_remove, $i;
            push @{$CLASSES{$classname}->{inner_classes}}, 
               {class_name => "$classname." . $cprop->{mapped_name}};
            $FUNCTIONS{"$classname.$propname"} = 
               delete $FUNCTIONS{"__$classname.$propname"};
         } 
         $i++;
      }
      for (reverse @to_remove){
         splice(@{$CLASSES{$classname}->{class_methods}}, $_, 1);
      }
   }
}

#
# Map a single instance or class field or method 
#
sub map_single_property {
   my ($class, $prop_name, $prop_val, 
      $description, $vars, $is_class_prop) = @_;
   if (!$FUNCTIONS{$prop_val}){
      if (!$is_class_prop){
         push @{$CLASSES{$class}->{instance_fields}}, { 
            field_name => $prop_name,
            field_description => $description,
            field_vars => $vars
         };
         return;
      } else {
         push @{$CLASSES{$class}->{class_fields}}, { 
            field_name => $prop_name,
            field_description => $description,
            field_vars => $vars
         };
         return;
      }
   }
   my %method;
   my $function = $FUNCTIONS{$prop_val};
   $function->{is_mapped} = 1;
   $method{mapped_name} = $prop_name;

   $method{$_} = $function->{$_} for 
      qw/ argument_list description vars /;

   if (!$is_class_prop){
      push @{$CLASSES{$class}->{instance_methods}}, \%method;
   } else {
      push @{$CLASSES{$class}->{class_methods}}, \%method;
   }
}



#
# Build up the full hierarchy of classes, including figuring out
# what methods are overridden by subclasses, etc
# PARAM: The JS source code
#
sub build_class_hierarchy {
   # Find out what is inherited
   for my $class (map($CLASSES{$_}, sort keys %CLASSES)){
      my $superclassname = $class->{extends};
      !$superclassname and next;
      my $superclass = $CLASSES{$superclassname};
      $class->{inherits} = {};
      while ($superclass){
         $class->{inherits}->{$superclassname} = {};
         my @instance_fields;
         my @instance_methods;

         &handle_instance_methods(
            $superclass, 
            $superclassname, 
            $class, 
            \@instance_methods);

         &handle_instance_fields(
            $superclass,
            $superclassname, 
            $class, 
            \@instance_fields );

         $superclassname = $superclass->{extends};
         if ($superclassname){
            $superclass = $CLASSES{$superclassname}
         } else {
            $superclass = undef;
         }
      }
   }
}

#
# This is just a helper function for build_class_hierarchy
# because that function was getting way oversized 
#
sub handle_instance_methods {
   my ($superclass, $superclassname, $class, $instance_methods) = @_;
   if ($superclass->{instance_methods}){
      INSTANCE_METHODS: 
      for my $base_method (@{$superclass->{instance_methods}}){
         for my $method (@{$class->{instance_methods}}){
            if ($$base_method{mapped_name} eq $$method{mapped_name}){
               # Carry over the description for overridden methods with
               # no description (to be javadoc compliant)
               if (($base_method->{description} or $base_method->{vars}) 
                     and not $method->{description}){
                  $method->{description} = $base_method->{description};
                  for my $varkey (keys(%{$base_method->{vars}})){
                     $method->{vars}->{$varkey} 
                        = $base_method->{vars}->{$varkey}
                           unless $method->{vars}->{$varkey};
                  }
               }
               next INSTANCE_METHODS;
            }
         }
         for (keys %{$class->{inherits}}){
            my $inherited = $class->{inherits}->{$_};
            for my $method (@{$inherited->{instance_methods}}){
               if ($$base_method{mapped_name} eq $method){
                  next INSTANCE_METHODS;
               }
            }
         }
         push @$instance_methods, $$base_method{mapped_name};
      }
      $class->{inherits}->
      {$superclassname}->{instance_methods} = $instance_methods;
   }
}

#
# This is just a helper function for build_class_hierarchy
# because that function was getting way oversized 
#
sub handle_instance_fields {
   my ($superclass, $superclassname, $class, $instance_fields) = @_;
   if ($superclass->{instance_fields}){
      INSTANCE_FIELDS: 
      for my $base_field  (@{$superclass->{instance_fields}}){
         for my $field (@{$class->{instance_fields}}){
            if ($field eq $base_field){
               next INSTANCE_FIELDS;
            }
         }
         push @$instance_fields, $base_field;
      }
      $class->{inherits}->{$superclassname}->
            {instance_fields} = $instance_fields;
   }
}

#
# Set all the class constructors
#
sub set_class_constructors {
   for my $classname (keys %CLASSES){
      my $constructor = $FUNCTIONS{$classname};
      $CLASSES{$classname}->{constructor_args} = 
         $constructor->{argument_list};
      $CLASSES{$classname}->{constructor_summary} = $constructor->{description};
      $CLASSES{$classname}->{constructor_params} = $constructor->{args};
      $CLASSES{$classname}->{constructor_vars} = $constructor->{vars} || {};
   }
}

# 
# Clear out everything from the parsed classes and functions
#
sub reset_parser {
	%CLASSES = ();
	%FUNCTIONS = ();
}

#
# Set global parameters for the parser
#
sub configure_parser {
   %CONFIG = @_;
}

#
# Run through the source and convert 'confusing' JavaScript constructs
# into ones that are understood by the parser, as well as stripping
# out unwanted comment blocks. 
#
# For example:
#  
#  Foo.prototype = { 
#     bar: function(){ return "Eep!"; },
#     baz: "Ha!"
#  } 
#
#  becomes
#
#  Foo.prototype.bar = function(){ return "Eep!"; };
#  Foo.prototype.baz = "Ha!";
#
sub preprocess_source {
   my ($src) = @_;

   
   # Convert:
   #     /** @constructor */
   #     Foo.Bar = function(){...}
   # to:
   #     /** @constroctor */
   #     Foo.Bar = function(){}
   #     /** @constructor */
   #     function Foo.Bar(){...}
   #
   # Note that we have to keep the original declaration so that Foo.Bar
   # can be recognized as a nested class. Yes, I know it's bad...
   $src =~ s!
      ($JSDOC_COMMENT\s*)
      (\w+(?:\.\w+)*?)
      \s*=
      (\s*function)(?=\s*$BAL_PAREN\s*\{)
      !index($1, '@constructor') == -1 ? "$1$2 = $3" : "$1$2 = function(){};\n$1$3 $2"!esgx;


   
   # remove all uninteresting comments, but only if they're not inside
   # of other comments     
   # (adapted from Jeffrey Friedl's "Mastering Regular Expressions"
   {
      no warnings;
      $src =~ s/
         ($NONQUOTE+|
            $JSDOC_COMMENT$NONQUOTE*|
            $DQUOTE$NONQUOTE*|
            $SQUOTE$NONQUOTE*)
         |$MLINE_COMMENT|$SLINE_COMMENT/$1/gx;
   }

   # Alter the prototype-initialization blocks
   while($src =~ s!
      (\w+(?:\.\w+)*)\.prototype
      \s*=\s*
      (\{
      .*
      )
      !
      my ($pre, $post) = &find_balanced_block('{', '}', $2);
      &deconstruct_prototype($1, $pre) . $post!esx){}
   
   $src =~ s!
      ($JSDOC_COMMENT\s*)
      ($FUNC_DEF)
      !&deconstruct_constructor($1, $2)!megx;

   $src;
}


#
# A helper to preprocess_source, change prototype-initialization
# blocks into multiple prototype-property assignments
#
sub deconstruct_prototype {
   my ($class, $src) = @_;
   $src =~ s/^\{(.*)\}$/$1/s;
   $src =~ s!
      (\w+)
      \s*:\s*
      (
      $FUNC_DEF
      |
      $FUNC_CALL
      |
      $LITERAL
      |
      \w+
      )
      \s*,?
   !$class.prototype.$1 = $2;!gsx;
   $src;
}

#
# Unpacks a constructor into separate calls
#
sub deconstruct_constructor {
   my ($doc, $func_def) = @_;
   return "$doc$func_def" unless $doc =~ /\@constructor/;
   my ($classname) = $func_def =~ /function\s+(\w+(?:\.\w+)*)/;
   $func_def =~ s/
      ($BAL_BRACE)
      /&deconstruct_inner_constructor($classname, $1)/emx;
   "$doc$func_def";
}

sub deconstruct_inner_constructor {
   my ($classname, $inner_src) = @_;
   $inner_src = substr($inner_src, 1, -1);
   my @doc_n_fnames = $inner_src =~ /($JSDOC_COMMENT?)\s*function\s+(\w+)/;
   $inner_src =~ s/
      ($JSDOC_COMMENT)?
      \s*
      var
      \s+
      (\w+)/&privatize_comment($1) . "\n$classname\.prototype\.$2"/egmx;

   $inner_src =~ s/
      ($JSDOC_COMMENT)?\s*
      ^\s*
      function
      \s+
      (\w+)
      /&privatize_comment($1) . "\n$classname\.prototype\.$2 = function"/egmx;

   { 
      no warnings;
      $inner_src =~ s/
         ($JSDOC_COMMENT\s*)?
         ^\s*this(?=\.)
         /$1$classname.prototype/gmx;
   }

   # Replace all bindings of private methods to public names
   for (my $i = 0; $i < @doc_n_fnames; $i += 2)
   {
      my ($doc, $fname) = @doc_n_fnames[$i, $i + 1];
      $inner_src =~ s/
         ($JSDOC_COMMENT\s*
         $classname\.prototype\.\w+)
         \s*=\s*
         $fname\s*[\n;]
         /$1 = function(){}/gx;

      $inner_src =~ s/
         ($classname\.prototype\.\w+)
         \s*=\s*
         $fname\s*[\n;]
         /$doc\n$1 = function(){}/gx;
   }
   "{}\n$inner_src";

}

sub privatize_comment {
   return "\n/** \@private */" unless $_[0];
   substr($_[0], 0, -2) . " \n\@private \n*/";
}

#
# This is here to stop perl from segfaulting from deep recursion in regexes
#
sub find_balanced_block {
   my ($open_token, $close_token, $text) = @_;
   my ($count, $open, $close) = (0, 0, 0);
   for (split //, $text){
      $count++;
      $open++ if $_ eq $open_token;
      $close++ if $_ eq $close_token;
      last unless ($open != $close);
   }
   warn "Unbalanced block\n" if ($open != $close);
   (substr($text, 0, $count), substr($text, $count)); 
}

1;
