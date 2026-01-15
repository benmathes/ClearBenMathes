define [], () ->
  # This structure requires some explanation:
  # lib/clear.coffee is a bit of a monolith. Within that
  # is how interelated all the legal terms of an offer/amendment/etc.
  # actually are. Every clear page is really just a subset of all the terms,
  # presented for easier digestion. We use the exact same Backbone.view
  # for all of them: ClearView will happily ignore any terms/graphs/etc.
  # that do not exist on any particular page.
  # A consequence of that, is that all the partials have no `assets do`
  # in them. If you added an `assets do`, you'd have an issue of multiple
  # views doing conflicting work.
  pages = {}
  for page in ['offer', 'amendment', 'how_much']
    pages[page] = ($$, $this) ->
      require ['lib/clear'], (ClearView) ->
        new ClearView el: $this
  pages
