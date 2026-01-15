class Presenter::Clear < Presenter::Base

  def pdf_title_style
    "s-h2 s-vgBottom3 s-vgTop3"
  end

  def pdf_term_title
    "s-h5 s-vgBottom0_5 s-vgTop1_5"
  end

  def section_title
    "u-fontSize24 s-grid-colSm24 js-sectionTitle"
  end

  def section_title_subtext
    "u-colorGray8 s-grid-colSm24 js-sectionTitleSubtext s-vgBorderBottom1 u-fontSize14 s-vgTop0_5"
  end

  def section_style_no_margin
    "s-grid js-termSection"
  end

  def section_style
    "#{section_style_no_margin} s-vgBottom8"
  end

  def page_title
    "u-fontSize52 u-fontWeight100"
  end

  def page_title_subtext
    "u-fontSize24 u-fontWeight200 u-colorGray8 s-vgTop1_5"
  end

  def page_title_wrapper
    "s-vgPadTop4 s-vgPadBottom4 u-textAlignCenter u-bgGray s-vgBottom4"
  end

  def term_style
    "js-clearTerm clearTerm"
  end

  def term_left
    "s-grid-colMd8 s-grid-break s-vgTop3"
  end

  def term_right
    "s-grid-colMd16 s-vgTop5"
  end

  def term_title
    's-h5 js-termTitle u-colorGray8 s-vgBottom0_5'
  end

  def term_value
    'js-termValue'
  end

  def term_title_input_class
    'js-termInput'
  end

  def description_style
    "u-colorGray8 termDescription js-termDescription"
  end

  def layout(page=:offer)
    {
      offer: 'single_column',
      amendment: 'single_column',
      landing: 'single_column',
      how_much: 'single_column',
    }[page]
  end

  def title(page=:offer)
    {
      offer: 'CLEAR Offer Letter',
      amendment: 'CLEAR Equity Amendment',
      landing: 'CLEAR and Fair Startup Equity',
      how_much: 'CLEAR: How Much Could Your Equity Be Worth?',
    }[page]
  end

  def layout_scheme(page=:offer)
    :white_all
  end

  def layout_size
    :large
  end

  def comparable_exits
    [
      {
        approx: 100_000_000,
        companies: [
          {
            name: 'Caviar',
            value: 90_1000_1000,
            url: 'https://angel.co/caviar'
          },
        ]
      },
      {
        approx: 500_000_000,
        companies: [
          {
            name: 'Dropcam',
            value: 555_000_000,
            url: 'https://angel.co/dropcam'
          },
          {
            name: 'MyFitnessPal',
            value: 475_000_000,
            url: 'https://angel.co/myfitnesspal'
          },
        ]
      },
      {
        approx: 1_000_000_000,
        companies: [
          {
            name: 'Twitch',
            value: 970_000_000,
            url: 'https://angel.co/twitch'
          },
          {
            name: 'New Relic',
            value: 1_060_000_000,
            url: 'https://angel.co/new-relic'
          },
        ]
      },
      {
        approx: 5_000_000_000,
        companies: [
          {
            name: 'Lending Club',
            value: 5_420_000_000,
            url: 'https://angel.co/lending-club'
          },
          {
            name: 'King (candy crush)',
            value: 5_900_000_000,
            url: 'https://angel.co/king-com'
          },
        ],
      },
      {
        approx: 10_000_000_000,
        companies: [
          {
            name: 'PeopleSoft',
            value: 10_300_000_000,
            url: 'https://angel.co/peoplesoft'
          },
          {
            name: 'Twitter',
            value: 14_200_000_000,
            url: 'https://angel.co/twitter'
          },
        ],
      }
    ]
  end

end
