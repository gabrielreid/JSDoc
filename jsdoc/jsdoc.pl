#!/usr/bin/perl -w

#
# This program makes use of the JSDoc module to make a JavaDoc equivalent
# for JavaScript. The template that is used is based on the JavaDoc
# doclet. This script only needs to be invoked with one or more 
# JS OO sourcefiles as command-line args.
#

use strict;
use HTML::Template;
use File::Copy;
use File::Basename;
use JSDoc;


use constant LOCATION => dirname($0) . '/';
use constant MAIN_TMPL => LOCATION . "main.tmpl";
use constant ALLCLASSES_TMPL => LOCATION . 'allclasses-frame.tmpl';
use constant ALLCLASSES_NOFRAME_TMPL => LOCATION . 'allclasses-noframe.tmpl';
use constant INDEX_TMPL => LOCATION . 'index.tmpl';
use constant DEST_DIR => 'js_docs_out/';
use constant STYLESHEET => 'stylesheet.css';
use constant HELPDOC => 'help-doc.html';
use constant INDEX_ALL_TMPL => LOCATION . 'index-all.tmpl';

use vars qw/ $TMPL $JS_SRC $CLASSES $DEFAULT_CLASSNAME @CLASSNAMES @INDEX /;

#
# Begin main execution
#

$TMPL = new HTML::Template( 
   die_on_bad_params => 0, 
   filename => MAIN_TMPL);

if (@ARGV < 1){
   &show_usage();
   exit(1);
}

mkdir(DEST_DIR);

# Load all of the JS source code and parse it into a code tree
&load_sources();
$CLASSES = &parse_code_tree(\$JS_SRC);
&output_class_templates();
&output_index_template();
&output_aux_templates();

# 
# End main execution
#

#
# Gather information for each class and output its template
#
sub output_class_templates {
   
   # Note the class name for later
   @CLASSNAMES = sort { $a->{classname} cmp $b->{classname}} 
      map {classname => $_}, keys %$CLASSES;

   for (my $i = 0; $i < @CLASSNAMES; $i++){
      my $classname = $CLASSNAMES[$i]->{classname};

      # Template Parameters
      my ($class, $subclasses, $class_summary, $constructor_params, 
         $next_class, $prev_class);

      $class= $$CLASSES{$classname};

      &add_to_index($class, $classname);

      # Set up the constructor and class information
      $constructor_params = $class->{constructor_params}
         or $constructor_params = [];
      $class_summary = $class->{constructor_summary};
      $class_summary =~ s/TODO:/<br><b>TODO:<\/b>/g if $class_summary;

      # Navbar information
      $next_class = $i + 1 < @CLASSNAMES ? $CLASSNAMES[$i + 1]->{classname} 
         : undef; 
      $prev_class = $i > 0 ? $CLASSNAMES[$i - 1]->{classname} : undef;

      # Find all the direct subclasses
      $subclasses = join( ',',
         map qq| <a href="$_.html">$_</a>|, @{&find_subclasses($classname)});
      
      # Set up the template and output it
      $TMPL->param(next_class => $next_class);
      $TMPL->param(prev_class => $prev_class);
      $TMPL->param(superclass => $class->{extends});
      $TMPL->param(constructor_args => $class->{constructor_args});
      $TMPL->param(constructor_params => $constructor_params);
      $TMPL->param(class_summary => $class_summary);
      $TMPL->param(classname => $classname);
      $TMPL->param(subclasses=> $subclasses);
      $TMPL->param(class_tree => &build_class_tree($classname, $CLASSES));
      $TMPL->param(fields => &map_fields($class));
      $TMPL->param(methods => &map_methods($class)); 
      $TMPL->param(method_inheritance => &map_method_inheritance($class));
      $TMPL->param(field_inheritance => &map_field_inheritance($class));
      open FILE, '>' . DEST_DIR . "$classname.html"
         or die "Couldn't open file to write : $!\n";
      print FILE $TMPL->output;
      close FILE;
   }
}


#
# Output all the non-class template files
#
sub output_aux_templates(){
   $TMPL = new HTML::Template( die_on_bad_params => 1, filename => ALLCLASSES_TMPL);
   $DEFAULT_CLASSNAME = $CLASSNAMES[0]->{classname};
   $TMPL->param(CLASSNAMES => \@CLASSNAMES);
   open FILE, '>' . DEST_DIR . "allclasses-frame.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;

   $TMPL = new HTML::Template( die_on_bad_params => 1, filename => ALLCLASSES_NOFRAME_TMPL);
   $DEFAULT_CLASSNAME = $CLASSNAMES[0]->{classname};
   $TMPL->param(CLASSNAMES => \@CLASSNAMES);
   open FILE, '>' . DEST_DIR . "allclasses-noframe.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;


   $TMPL = new HTML::Template( die_on_bad_params => 1, filename => INDEX_TMPL);
   $TMPL->param(DEFAULT_CLASSNAME => $DEFAULT_CLASSNAME);
   open FILE, '>' . DEST_DIR . "index.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;

   copy (LOCATION . STYLESHEET, DEST_DIR . STYLESHEET);
   copy (LOCATION . HELPDOC, DEST_DIR . HELPDOC);
}


# 
# Build the tree representation of the inheritance
# PARAM: Name of the class
#
sub build_class_tree {
   my $classname  = shift;
   my $class = $$CLASSES{$classname};
   my $tree = "";
   my @family;
   push @family, $classname;
   while ($class->{extends} and $class->{extends} ne ""){
      push @family, "<a href=\"" . $class->{extends} . ".html\">" . 
	 $class->{extends} . "</a>";
      $class = $$CLASSES{$class->{extends}};
   }
   push @family, "Object";
   my $indent = 3;
   $tree = (pop @family) . "\n";
   my $name = $_;
   while ($name = pop (@family)){
      $tree .= " " x $indent; 
      $tree .= "|\n";

      $tree .= " " x $indent;
      $tree .= "+--";
      $name eq $classname and $tree .= "<b>";
      $tree .= $name;
      $name eq $classname and $tree .= "</b>";
      $tree .= "\n";
      $indent += 6;
   }
   $tree;
}

#
# Shown if no commandline args are given
#
sub show_usage(){
   warn "Usage: jsdoc <js_sourcefile>+\n";
}

# 
# Take all the command line args as filenames and add them to the source
#
sub load_sources(){
   while(<>){
      $JS_SRC .= $_;
   }
}

#
# Once all sources have been parsed, finds all subclasses
# of $classname
#
sub find_subclasses(){
   my ($classname) = @_;
   my @subclasses;
   for my $class (keys %$CLASSES){
      my $subclassname = $$CLASSES{$class}->{extends};
      if ($$CLASSES{$class}->{extends} and 
	 $$CLASSES{$class}->{extends} eq $classname){
	    push @subclasses,  $class;
      }
   }
   \@subclasses;
}

#
# Make a summary of a description, cutting it off either at the first
# double newline or the first period.
# PARAM: $description
#
sub get_summary {
   my ($description) = @_;
   my $summary;
   if ($description){
      ($summary) = $description =~ /^(.*?(?:[\?\!\.]|\n\n)).*$/gxs
	 or $summary = $description;
   } else {
      $summary = "";
   }
   $summary;
}


#
# Set up all the instance and class methods for one template
# PARAM: A reference to a class
#
sub map_methods{
   my $class = shift;
   my @methods;
   for my $method ( 
      sort {$a->{mapped_name} cmp $b->{mapped_name} }  
      @{$class->{instance_methods}}){
         my @args;
         for (@{$method->{args}}){
            push @args, $_;
         }
         push @methods, {
            method_description => $method->{description} ,
            method_summary => &get_summary($method->{description}),
            method_name => $method->{mapped_name},
            method_arguments => $method->{argument_list},
            method_params => \@args,
            method_returns => $method->{returns},
            is_class_method => 0,
            is_private => $method->{is_private}
            };
   }

   for my $method(
      sort {$a->{mapped_name} cmp $b->{mapped_name} } 
      @{$class->{class_methods}}){
         my @args;
         for (@{$method->{args}}){
            push @args, $_;
         }
         push @methods, {
            method_description => $method->{description} ,
            method_summary => &get_summary($method->{description}),
            method_name => $method->{mapped_name},
            method_arguments => $method->{argument_list},
            method_params => \@args,
            method_returns => $method->{returns},
            is_class_method => 1
            }; 
   }
   \@methods;
}


#
# Set up all the instance and class methods for one template
# PARAM: A reference to a class
#
sub map_fields {
   my $class = shift;
   my @fields;
   # Set up the instance fields
   for (sort {$a->{field_name} cmp $b->{field_name} } 
      @{$class->{instance_fields}}){
         push @fields, { 
         field_name => $_->{field_name}, 
         field_description => $_->{field_description}, 
         field_summary => &get_summary($_->{field_description}),
         is_class_field => 0
         };
   }


   # Set up the class fields 
   if ($class->{class_fields}){
      for (sort {$a->{field_name} cmp $b->{field_name} } 
         @{$class->{class_fields}}){
            push @fields, { 
               field_name => $_->{field_name}, 
               field_description => $_->{field_description}, 
               field_summary => &get_summary($_->{field_description}),
               is_class_field => 1
               };
      }
   }
   \@fields;
}

#
# Map all the inherited methods to a template parameter
# PARAM: A reference to a class
#
sub map_method_inheritance {
   my $class = shift;
   my @method_inheritance; 
   # Set up the inherited methods
   if ($class->{inherits}){
      my $superclassname = $class->{extends};
      my $superclass = $$CLASSES{$superclassname};
      while ($superclass){
         my $methods = 
            $class->{inherits}->{$superclassname}->{instance_methods};
         if ($methods and @$methods){
            push @method_inheritance, {
               superclass_name => $superclassname,
               inherited_methods => join(', ', 
                     map(qq|<a href="$superclassname.html#$_">$_</a>|, @$methods))};
         }
         $superclassname = $superclass->{extends};
         if ($superclassname){
            $superclass = $$CLASSES{$superclassname};
         } else {
            $superclass = undef;
         }
      }
   }
   \@method_inheritance;
}

#
# Map all the inherited fields to a template parameter
# PARAM: A reference to a class
#
sub map_field_inheritance {
   my $class = shift;
   my @field_inheritance;
   # Set up the inherited fields 
   if ($class->{inherits}){
      my $superclassname = $class->{extends};
      my $superclass = $$CLASSES{$superclassname};
      while ($superclass){
         my $fields = $class->{inherits}->{$superclassname}->{instance_fields};
         if ($fields and @$fields){
            push @field_inheritance, 
               {
                  superclass_name => $superclassname,
                  inherited_fields => join(', ', 
                     map(qq|<a href="$superclassname.html#$_->{field_name}">$_->{field_name}</a>|, @$fields))};
         }
         $superclassname = $superclass->{extends};
         if ($superclassname){
            $superclass = $$CLASSES{$superclassname};
         } else {
            $superclass = undef;
         }
      }
   }
   \@field_inheritance;
}

#
# Adds a class's information to the global INDEX list 
#
sub add_to_index {
   my ($class, $classname) = @_;
   push @INDEX, { name => $classname, class => $classname, type => '', linkname => '' };
   if (!$class->{constructor_args}){
      $class->{constructor_args} = '';
   }
   push @INDEX, 
      {
         name => "$classname$class->{constructor_args}",
         class => $classname,
         type => 'Constructor in ',
         linkname => 'constructor_detail'
      };
   for my $method(@{$class->{class_methods}}){
      push @INDEX, 
         {
            name => "$method->{mapped_name}$method->{argument_list}", 
            class => $classname,
            type => 'Class method in ',
            linkname => $method->{mapped_name}
         };
   }
   for my $method (@{$class->{instance_methods}}){
      push @INDEX, 
         {
            name => "$method->{mapped_name}$method->{argument_list}",
            class => $classname,
            type => 'Instance method in ',
            linkname => $method->{mapped_name}
         };
   }
   for my $class_field (@{$class->{class_fields}}){
      push @INDEX, 
         {
            name => $class_field->{field_name},
            class => $classname,
            type => 'Class field in ',
            linkname => $class_field->{field_name}
         };
   }
   for my $instance_field (@{$class->{instance_fields}}){
      push @INDEX,
         {
            name => $instance_field->{field_name},
            class => $classname,
            type => 'Instance field in ',
            linkname => $instance_field->{field_name}
         };
   }
}

#
# Outputs the index page
#
sub output_index_template { 
   @INDEX = sort {$a->{name} cmp $b->{name}} @INDEX;
   my %letters;
   for my $item (@INDEX){
      my $letter = uc(substr($item->{name}, 0, 1));
      if ($letter eq ''){
         $letter = uc(substr($item->{class}, 0, 1));
      }
      push @{$letters{$letter}}, $item; 
   }
   
   my $letter_list = [map {letter_name => $_}, sort {$a cmp $b} keys %letters];
   $TMPL = new HTML::Template( die_on_bad_params => 1, filename => INDEX_ALL_TMPL);
   $TMPL->param( letters => $letter_list);
   $TMPL->param(index_list => [map {letter => $_->{letter_name}, value => $letters{$_->{letter_name}}}, @{$letter_list}]);
   
   open FILE, '>' . DEST_DIR . "index-all.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;
}
