#!/usr/bin/perl -w

#
# This program makes use of the JSDoc module to make a JavaDoc equivalent
# for JavaScript. The template that is used is based on the JavaDoc
# doclet. This program only needs to be invoked with one or more 
# JS OO sourcefiles as command-line args.
#

use strict;
use HTML::Template;
use File::Copy;
use File::Basename;
use Getopt::Long;
use File::Find;
use Data::Dumper;
use JSDoc;


use constant LOCATION => dirname($0) . '/';
use constant MAIN_TMPL => LOCATION . "main.tmpl";
use constant ALLCLASSES_TMPL => LOCATION . 'allclasses-frame.tmpl';
use constant ALLCLASSES_NOFRAME_TMPL => LOCATION . 'allclasses-noframe.tmpl';
use constant TREE_TMPL => LOCATION . 'overview-tree.tmpl';
use constant OVERVIEW_TMPL => LOCATION . 'overview-summary.tmpl';
use constant INDEX_TMPL => LOCATION . 'index.tmpl';
use constant DEFAULT_DEST_DIR => 'js_docs_out/';
use constant STYLESHEET => 'stylesheet.css';
use constant HELP_TMPL => 'help-doc.tmpl';
use constant INDEX_ALL_TMPL => LOCATION . 'index-all.tmpl';

use vars qw/ $TMPL $CLASSES $DEFAULT_CLASSNAME @CLASSNAMES @INDEX 
            %CLASS_ATTRS_MAP %METHOD_ATTRS_MAP %OPTIONS /;

#
# Begin main execution
#

&parse_cmdline;
&initialize_param_maps;

do '.jsdoc_config';
warn "Error parsing config file: $@\n" if $@;

$TMPL = new HTML::Template( 
   die_on_bad_params => 0, 
   filename => MAIN_TMPL);

my @sources;
if (@ARGV < 1 || $OPTIONS{HELP} || !(@sources = &load_sources())){
   warn "No sourcefiles supplied\n" if !$OPTIONS{HELP};
   &show_usage();
   exit(1);
}

mkdir($OPTIONS{OUTPUT})
   or die "Can't create output directory $OPTIONS{OUTPUT}: $!\n" 
   unless (-e $OPTIONS{OUTPUT} && -d $OPTIONS{OUTPUT});

# Parse the code tree
$CLASSES = &parse_code_tree(@sources);
&output_class_templates();
&output_index_template();
&output_aux_templates();
&output_tree_template();

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
      my ($class, $subclasses, $class_summary, @constructor_params, 
         $next_class, $prev_class);

      $class= $$CLASSES{$classname};

      &add_to_index($class, $classname);

      # Set up the constructor and class information
      &resolve_synonyms($class->{constructor_vars});
      @constructor_params = &fetch_args($class->{constructor_vars}, $class->{constructor_args});
      $class_summary = &resolve_inner_links($class->{constructor_summary});
      $class_summary =~ s/TODO:/<br><b>TODO:<\/b>/g if $class_summary;
      $class_summary .= &format_class_attributes($class->{constructor_vars});

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
      $TMPL->param(constructor_params => \@constructor_params);
      $TMPL->param(class_summary => $class_summary);
      $TMPL->param(classname => $classname);
      $TMPL->param(subclasses=> $subclasses);
      $TMPL->param(class_tree => &build_class_tree($classname, $CLASSES));
      $TMPL->param(fields => &map_fields($class));
      $TMPL->param(methods => &map_methods($class)); 
      $TMPL->param(method_inheritance => &map_method_inheritance($class));
      $TMPL->param(field_inheritance => &map_field_inheritance($class));
      $TMPL->param(project_name => $OPTIONS{PROJECT_NAME});
      $TMPL->param(page_footer => $OPTIONS{PAGE_FOOTER});
      open FILE, '>' . $OPTIONS{OUTPUT} . "$classname.html"
         or die "Couldn't open file to write : $!\n";
      print FILE $TMPL->output;
      close FILE;
   }
}


#
# Output all the non-class template files
#
sub output_aux_templates(){
   
   unless ($OPTIONS{LOGO} and -f $OPTIONS{LOGO} and -r $OPTIONS{LOGO}){
      $OPTIONS{LOGO} and warn "Can't read $OPTIONS{LOGO}";
      $OPTIONS{LOGO} = '';
   }
   $OPTIONS{LOGO} and copy $OPTIONS{LOGO}, $OPTIONS{OUTPUT};

   my $summary = '';
   if ($OPTIONS{PROJECT_SUMMARY}){
      if (-f $OPTIONS{PROJECT_SUMMARY} and 
            open SUMMARY, $OPTIONS{PROJECT_SUMMARY}){
         local $/ = undef;
         $summary = <SUMMARY>;
         close SUMMARY;
      } else {
         warn "Can't open $OPTIONS{PROJECT_SUMMARY}";
      }
   }

   $TMPL = new HTML::Template( die_on_bad_params => 1, 
      filename => ALLCLASSES_TMPL);
   $DEFAULT_CLASSNAME = $CLASSNAMES[0]->{classname};
   $TMPL->param(CLASSNAMES => \@CLASSNAMES);
   $TMPL->param(project_name => $OPTIONS{PROJECT_NAME});
   $TMPL->param(logo => basename($OPTIONS{LOGO}));
   open FILE, ">$OPTIONS{OUTPUT}allclasses-frame.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;

   $TMPL = new HTML::Template( die_on_bad_params => 1, 
      filename => ALLCLASSES_NOFRAME_TMPL);
   $DEFAULT_CLASSNAME = $CLASSNAMES[0]->{classname};
   $TMPL->param(CLASSNAMES => \@CLASSNAMES);
   $TMPL->param(project_name => $OPTIONS{PROJECT_NAME});
   $TMPL->param(logo => basename($OPTIONS{LOGO}));
   open FILE, ">$OPTIONS{OUTPUT}allclasses-noframe.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;


   $TMPL = new HTML::Template( die_on_bad_params => 1, filename => INDEX_TMPL);
   if ($summary){
      $TMPL->param(DEFAULT_CLASSNAME => "overview-summary");
   } else {
      $TMPL->param(DEFAULT_CLASSNAME => $DEFAULT_CLASSNAME);
   }
   open FILE, ">$OPTIONS{OUTPUT}index.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;

   $TMPL = new HTML::Template( die_on_bad_params => 1, filename => HELP_TMPL);
   $TMPL->param(project_name => $OPTIONS{PROJECT_NAME});
   $TMPL->param(page_footer => $OPTIONS{PAGE_FOOTER});
   open FILE, ">$OPTIONS{OUTPUT}help-doc.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;
   copy (LOCATION . STYLESHEET, $OPTIONS{OUTPUT} . STYLESHEET);

   $TMPL = new HTML::Template( die_on_bad_params => 1, 
      filename => OVERVIEW_TMPL);
   $TMPL->param(project_name => $OPTIONS{PROJECT_NAME});
   $TMPL->param(page_footer => $OPTIONS{PAGE_FOOTER});
   $TMPL->param(project_summary => $summary);
   open FILE, ">$OPTIONS{OUTPUT}overview-summary.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;

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
   print qq{Usage: jsdoc [OPTIONS] <js sourcefiles and/or directories>+
   
   -h | --help          Show this message and exit
   -r | --recursive     Recurse through given directories
   -p | --private       Show private methods
   -d | --directory     Specify output directory (defaults to js_docs_out)


   --page-footer        Specify (html) footer string that will be added to 
                        all docs
   --project-name       Specify project name for that will be added to docs 
   --logo               Specify a path to a logo to be used in the docs 
   --project-summary    Specify a path to a text file that contains an 
                        overview summary of the project \n};

}

# 
# Take all the command line args as filenames and add them to @SOURCESFILES 
#
sub load_sources(){
   my (@filenames, @sources);
   for my $arg (@ARGV){
      if (-d $arg){
         $arg =~ s/(.*[^\/])$/$1\//; 
         find( { 
            wanted => sub { 
                  push @filenames, $_ if 
                     (-f and -r and /.+\.js$/i) && 
                     (/$arg[^\/]+$/ || $OPTIONS{RECURSIVE}) 
               }, 
            no_chdir => 1 }, $arg);
      } elsif (-f $arg){
         push @filenames, $arg;
      }   
   }
   for (@filenames){
      print "Loading sources from $_\n";
      open SRC, "<$_" or  (warn "Can't open $_, skipping: $!\n" and next);
      local $/ = undef;
      push @sources, \<SRC>;
      close SRC;
   }
   @sources;
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
# double newline or the first period followed by whitespace.
# PARAM: $description
#
sub get_summary {
   my ($description) = @_;
   my $summary;
   if ($description){
      ($summary) = $description =~ /^(.*?(?:[?!.](?=\s)|\n\n)).*$/gs
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
         &resolve_synonyms($method->{vars}); 
         next if (!$OPTIONS{PRIVATE} && $method->{vars}->{private});
         $method->{vars}->{returns}[0] = 
            $method->{vars}->{returns}[0] || $method->{vars}->{return};
         my @args = &fetch_args($method->{vars}, $method->{argument_list});
         push @methods, {
            method_description => &resolve_inner_links($method->{description}),
            method_summary => &resolve_inner_links(
               &get_summary($method->{description})),
            method_name => $method->{mapped_name},
            method_arguments => $method->{argument_list},
            method_params => \@args,
            method_returns => ref($method->{vars}->{returns}[0]) eq 'ARRAY' ? $method->{vars}->{returns}[0][0] : $method->{vars}->{returns}[0],
            is_class_method => 0,
            is_private => defined($method->{vars}->{private}), 
            attributes => &format_method_attributes($method->{vars}),
            type => &map_return_type($method)
            };
   }
   for my $method ( sort {$a->{mapped_name} cmp $b->{mapped_name} } 
      @{$class->{class_methods}}){
         &resolve_synonyms($method->{vars}); 
         next if (!$OPTIONS{PRIVATE} && $method->{vars}->{private});
         my @args = &fetch_args($method->{vars}, $method->{argument_list});
         push @methods, {
            method_description => &resolve_inner_links($method->{description}),
            method_summary => &resolve_inner_links(
               &get_summary($method->{description})),
            method_name => $method->{mapped_name},
            method_arguments => $method->{argument_list},
            method_params => \@args,
            method_returns => $method->{vars}->{returns}[0],
            is_class_method => 1,
            is_private => defined($method->{vars}->{private}), 
            attributes => &format_method_attributes($method->{vars}),
            type => &map_return_type($method)
            }; 
   }
   \@methods;
}

#
# Map a function return type
#
sub map_return_type {
   my ($method) = @_;
   if ($method->{vars}->{type}[0]){
      my ($name) = $method->{vars}->{type}[0] =~ /(\w+)/;
      if ($$CLASSES{$name}){
         return qq|<a href="$name.html">$name</a>|;
      }
      return $name;
   }
   return 'function';
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
         &resolve_synonyms($_->{field_vars});
         next if (!$OPTIONS{PRIVATE} && $_->{field_vars}->{private});
         push @fields, { 
         field_name => $_->{field_name}, 
         field_description => &resolve_inner_links($_->{field_description}), 
         field_summary => &resolve_inner_links(
            &get_summary($_->{field_description})),
         is_final => defined($_->{field_vars}->{final}),
         is_private => defined($_->{field_vars}->{private}),
         is_class_field => 0,
         type => &map_field_type($_)
         };
   }


   # Set up the class fields 
   if ($class->{class_fields}){
      for (sort {$a->{field_name} cmp $b->{field_name} } 
         @{$class->{class_fields}}){
            &resolve_synonyms($_->{field_vars});
            next if (!$OPTIONS{PRIVATE} && $_->{field_vars}->{private});
            push @fields, { 
               field_name => $_->{field_name}, 
               field_description => &resolve_inner_links( 
                  $_->{field_description}), 
               field_summary => &resolve_inner_links(
                  &get_summary($_->{field_description})),
               is_final => defined($_->{field_vars}->{final}),
               is_private => defined($_->{field_vars}->{private}),
               is_class_field => 1,
               type => &map_field_type($_)
               };
      }
   }
   \@fields;
}

#
# Map a field type
#
sub map_field_type {
   my ($field) = @_;
   if ($field->{field_vars}->{type}[0]){
      my ($name) = $field->{field_vars}->{type}[0] =~ /(\w+)/;
      if ($$CLASSES{$name}){
         return qq|<a href="$name.html">$name</a>|;
      }
      return $name;
   }
   return 'var';
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
                     map(qq|<a href="$superclassname.html#$_">$_</a>|, &filter_private_methods($methods, $superclassname)))};
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
                     map(qq|<a href="$superclassname.html#$_">$_</a>|, &filter_private_fields($fields, $superclassname)))};
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
# Filter out private inherited methods
#
sub filter_private_methods {
   my ($methods, $superclassname) = @_;
   my @visible_methods;
   for my $method(@$methods){
      for my $super_method (@{$$CLASSES{$superclassname}->{instance_methods}}){
         push @visible_methods, $method 
            if $method eq $super_method->{mapped_name} and 
               (!$super_method->{vars}->{private} || $OPTIONS{PRIVATE});
      }
   }
   @visible_methods;
}

#
# Filter out private inherited fields
#
sub filter_private_fields {
   my ($fields, $superclassname) = @_;
   my @visible_fields;
   for my $field (map {$_->{field_name}} @$fields){
      for my $super_field(@{$$CLASSES{$superclassname}->{instance_fields}}){
         push @visible_fields, $field
            if $field eq $super_field->{field_name} and
               (!$super_field->{field_vars}->{private} || $OPTIONS{PRIVATE});
      }
   }
   @visible_fields;
}

#
# Adds a class's information to the global INDEX list 
#
sub add_to_index {
   my ($class, $classname) = @_;
   push @INDEX, { 
      name => $classname, 
      class => $classname, 
      type => '', linkname => '' 
   };

   if (!$class->{constructor_args}){
      $class->{constructor_args} = '';
   } else {
      push @INDEX, 
         {
            name => "$classname$class->{constructor_args}",
            class => $classname,
            type => 'Constructor in ',
            linkname => 'constructor_detail'
         };
   }
   for my $method(@{$class->{class_methods}}){
      push @INDEX, 
         {
            name => "$method->{mapped_name}$method->{argument_list}", 
            class => $classname,
            type => 'Class method in ',
            linkname => $method->{mapped_name}
         } unless ($method->{vars}->{private} and not $OPTIONS{PRIVATE});
   }
   for my $method (@{$class->{instance_methods}}){
      push @INDEX, 
         {
            name => "$method->{mapped_name}$method->{argument_list}",
            class => $classname,
            type => 'Instance method in ',
            linkname => $method->{mapped_name}
         } unless ($method->{vars}->{private} and not $OPTIONS{PRIVATE});

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
   $TMPL = 
      new HTML::Template( die_on_bad_params => 1, filename => INDEX_ALL_TMPL);
   $TMPL->param( letters => $letter_list);
   $TMPL->param(project_name => $OPTIONS{PROJECT_NAME});
   $TMPL->param(page_footer => $OPTIONS{PAGE_FOOTER});
   $TMPL->param(index_list => [
      map {
         letter => $_->{letter_name}, 
         value => $letters{$_->{letter_name}}
      }, @{$letter_list}]);
   
   open FILE, '>' . $OPTIONS{OUTPUT} . '/index-all.html'
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;
}

#
# Recursively builds up the overview tree
#
sub build_tree 
{
   my $parentclassname = shift || '';
   my $ret = "";
   for my $cname (map {$_->{classname}} @CLASSNAMES) 
   {
      next if $cname eq '[default context]';
      my $class = $$CLASSES{$cname};
      my $parent = $class->{extends} || '-';
      if (!($parentclassname || $class->{extends}) 
            or ($parent eq $parentclassname))
      {
         $ret .= qq{
            <LI TYPE="circle">
               <A HREF="$cname.html">
            <B>$cname</B></A></LI>
         };
         my $childrentree .= &build_tree($cname);		
         $ret = "$ret<UL>$childrentree</UL>" unless not $childrentree;
      }
   }
   $ret = "<UL>$ret</UL>" unless not $ret;
   $ret;
}

#
# Outputs the overview tree
#
sub output_tree_template {
   $TMPL = new HTML::Template( 
      die_on_bad_params => 0, 
      filename => TREE_TMPL);
   my $tree = &build_tree();
   $TMPL->param(classtrees => $tree);
   $TMPL->param(project_name => $OPTIONS{PROJECT_NAME});
   $TMPL->param(page_footer => $OPTIONS{PAGE_FOOTER});
   open FILE, '>' . $OPTIONS{OUTPUT} . "overview-tree.html"
      or die "Couldn't open file to write : $!\n";
   print FILE $TMPL->output;
   close FILE;
}

#
# Formats additional non-standard attributes for methods according to user 
# configuration
#
sub format_method_attributes {
   my ($attrs) = shift;
   my $attributes = '';
   while (my ($name, $val) = each %{$attrs}) {
      $attributes .= &{$METHOD_ATTRS_MAP{$name}}($val) 
         if $METHOD_ATTRS_MAP{$name};
   }
   $attributes;
}

#
# Formats additional non-standard attributes for classes according to user 
# configuration
#
sub format_class_attributes {
   my ($attrs) = shift;
   my $attributes = '<br/>';
   while (my ($name, $val) = each %{$attrs}) {
      $attributes .= &{$CLASS_ATTRS_MAP{$name}}($val) 
         if $CLASS_ATTRS_MAP{$name};
   }
   $attributes;
}


#
# Parses the command line options
#
sub parse_cmdline {
   $OPTIONS{OUTPUT} = DEFAULT_DEST_DIR;
   $OPTIONS{PROJECT_NAME} = '';
   $OPTIONS{COPYRIGHT} = '';
   $OPTIONS{PROJECT_SUMMARY} = '';
   $OPTIONS{LOGO} = '';
   GetOptions(
      'private|p'          => \$OPTIONS{PRIVATE},
      'directory|d=s'      => \$OPTIONS{OUTPUT},
      'help|h'             => \$OPTIONS{HELP},
      'recursive|r'        => \$OPTIONS{RECURSIVE},
      'page-footer=s'      => \$OPTIONS{PAGE_FOOTER},
      'project-name=s'     => \$OPTIONS{PROJECT_NAME},
      'project-summary=s'  => \$OPTIONS{PROJECT_SUMMARY},
      'logo=s'             => \$OPTIONS{LOGO}
   );
   $OPTIONS{OUTPUT} =~ s/([^\/])$/$1\//;
}

#
# Resolves links for {@link } items
#
sub resolve_inner_links {
   my $doc = shift;
   $doc =~ s{\{\@link\s+([^\}]+)\}}{&format_link($1)}eg if $doc;
   return $doc;
}

#
# Formats a {@link } item
#
sub format_link {
   my ($link) = shift;
   $link =~ s/\s*(\S+)\s*/$1/;
   $link =~ s/<[^>]*>//g;
   my ($class, $method) = $link =~ /(\w+)?(?:#(\w+))?/;
   if (!$method){
      "<a href=\"$class.html#\">$class<\/a>";
   } else {
      if ($class){
         "<a href=\"$class.html#$method\">$class.$method()</a>";
      }
      else {
         "<a href=\"#$method\">$method()</a>";
      }
   }
}

#
# Initializes the customizable maps for @attributes
#
sub initialize_param_maps {
   %CLASS_ATTRS_MAP  = (
      author =>
         sub {
            '<DT><B>Author:</B>' .
               join(',', @{$_[0]}) . '<P/>'
         },

      deprecated =>
         sub {
            '<DT><B>Deprecated.</B><I>' . ($_[0] ? $_[0]->[0] : '') . 
            '</I><P/>';
         },
      see =>
         sub {
            '<DT><B>See:</B><DD>- ' .
            join('</DD><DD>- ', map {&format_link($_)} @{$_[0]}) . "</DD><P/>"
         },
      version =>
         sub {
            '<DT><B>Version: </B>' .
               join(',', @{$_[0]}) . '<P/>'
         },
      requires =>
         sub {
            '<DT><B>Requires:</B><DD>- ' .
            join('</DD><DD>- ', map {&format_link($_)} @{$_[0]}) . "</DD><P/>"
         }
   );
   
   %METHOD_ATTRS_MAP = (
      throws => 
         sub { 
         '<DT><DT><B>Throws:</B><DD>- ' .  
         join('<DD>- ', @{$_[0]}) . '<P/>'
      },
      deprecated =>
         sub {
            '<DT><B>Deprecated.</B><I>' . ($_[0] ? $_[0]->[0] : '') . 
            '</I><P/>';
         },
      see =>
         sub {
            '<DT><B>See:</B><DD>- ' .
            join('</DD><DD>- ', map {&format_link($_)} @{$_[0]}) . "</DD><P/>"
         }
   );
   $METHOD_ATTRS_MAP{exception} = $METHOD_ATTRS_MAP{throws};
}


# 
# Parse the @param or @argument values into name/value pairs and 
# return the list of them
#
sub fetch_args {
   my ($vars, $arg_list) = @_;
   return unless $vars and $arg_list;
   my (@args, %used);
   for my $arg (split /\W+/, ($arg_list =~ /\(([^)]*)/)[0]){
      for (@{$vars->{param}}){
         my ($name, $value) = (/(\w+)(.*)/)[0, 1];
         next unless $name eq $arg;
         $used{$name} = 1;
         push @args, {varname => $name, vardescrip => $value};
      }
   }
   for (@{$vars->{param}}){
      my ($name, $value) = (/(\w+)(.*)/)[0, 1];
      next if $used{$name};
      push @args, {varname => $name, vardescrip => $value};
   }
   @args;
}

sub resolve_synonyms {
   my ($item) = @_;
   $item->{param} = $item->{param} || $item->{argument};
   $item->{returns} = $item->{return} || $item->{returns};
   $item->{final} = $item->{final} || $item->{const};
}
