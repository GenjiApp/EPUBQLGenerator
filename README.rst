=================
 EPUBQLGenerator
=================

EPUBQLGenerator is Quick Look Generator for EPUB.


Install
=======

Copy EPUBQLGenerator.qlgenerator to ``/Library/QuickLook`` or ``~/Library/QuickLook``.


Restrictions
============

#. Doesn't apply CSS
#. Previews up to 10 HTML files per a EPUB
#. Shows up to 10 images per a HTML file


User Preferences
================

You can change the default behavior above.

On Terminal.app, by typing command as follows, you can change the maximum number of loading HTML file::

   defaults write jp.genji.qlgenerator.EPUBQLGenerator MaximumNumberOfLoadingHTML -integer 5

If ``-1`` is specified, all of HTML are previewed.

By typing command as follows, you can change the maximum number of loading image::

   defaults write jp.genji.qlgenerator.EPUBQLGenerator MaximumNumberOfLoadingImage -integer 5

If ``-1`` is specified, all of images are shown.
