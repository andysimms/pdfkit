{EventEmitter} = require 'events'
LineBreaker = require 'linebreak'

class LineWrapper extends EventEmitter
    constructor: (@document, options) ->
        @indent      = options.indent or 0
        @charSpacing = options.characterSpacing or 0
        @wordSpacing = options.wordSpacing is 0
        @columns     = options.columns or 1
        @columnGap   = options.columnGap ? 18 # 1/4 inch
        @lineWidth   =  (options.width - (@columnGap * (@columns - 1))) / @columns
        @startX      = @document.x
        @startY      = @document.y
        @column      = 1
        
        # calculate the maximum Y position the text can appear at
        @maxY = @startY + options.height
        
        # handle paragraph indents
        @on 'firstLine', (options) =>
            # if this is the first line of the text segment, and
            # we're continuing where we left off, indent that much
            # otherwise use the user specified indent option
            indent = @document._continuedX ? @indent
            @document.x += indent
            @lineWidth -= indent
            
            @once 'line', =>
                @document.x -= indent
                @lineWidth += indent
                @document._continuedX = null
        
        # handle left aligning last lines of paragraphs
        @on 'lastLine', (options) =>
            align = options.align
            options.align = 'left' if align is 'justify'
            @lastLine = true
            
            @once 'line', =>
                @document.y += options.paragraphGap or 0
                options.align = align
                @lastLine = false
        
    wrap: (text, options) ->
        # override options from previous continued fragments
        @indent      = options.indent           if options.indent?
        @charSpacing = options.characterSpacing if options.characterSpacing?
        @wordSpacing = options.wordSpacing      if options.wordSpacing?
        
        # make sure we're actually on the page 
        # and that the first line of is never by 
        # itself at the bottom of a page (orphans)
        nextY = @document.y + @document.currentLineHeight(true)
        if @document.y > @maxY or nextY > @maxY
            @nextSection()
        
        # word width cache
        wordWidths = {}
        @emit 'sectionStart', options, this
        
        breaker = new LineBreaker(text)
        last = null
        buffer = ''
        textWidth = 0
        wc = 0
        
        y = @document.y # used to reset Y pos if options.continued (below)
        emitLine = =>
            options.textWidth = textWidth + @wordSpacing * (wc - 1)
            options.wordCount = wc
            options.lineWidth = @lineWidth
            y = @document.y
            @emit 'line', buffer, options, this
        
        while bk = breaker.nextBreak()
            if not last? or last.required
                @emit 'firstLine', options, this
                spaceLeft = @lineWidth
                
            word = text.slice(last?.position or 0, bk.position)
            w = wordWidths[word] ?= @document.widthOfString(word, this) + @charSpacing + @wordSpacing
            
            if w <= spaceLeft
                buffer += word
                textWidth += w
                wc++
                            
            if bk.required or w > spaceLeft
                if bk.required
                    @emit 'lastLine', options, this
                
                emitLine()
                
                # if we've reached the edge of the page, 
                # continue on a new page or column
                if @document.y + @document.currentLineHeight(true) > @maxY
                    @nextSection()
                
                # reset the space left and buffer
                if bk.required
                    buffer = ''
                    textWidth = 0
                    wc = 0
                else
                    # reset the space left and buffer
                    spaceLeft = @lineWidth - w
                    buffer = word
                    textWidth = w
                    wc = 1
            else
                spaceLeft -= w
                
            last = bk
            
        if wc > 0
            @emit 'lastLine', options, this
            emitLine()
                
        @emit 'sectionEnd', options, this
        
        # if the wrap is set to be continued, save the X position
        # to start the first line of the next segment at, and reset
        # the y position
        if options.continued is yes
            @document._continuedX = textWidth
            @document.y = y
                    
    nextSection: (options) ->
        @emit 'sectionEnd', options, this
        
        if ++@column > @columns
            @document.addPage()
            @column = 1
            @startY = @document.page.margins.top
            @maxY = @document.page.maxY()
            @document.x = @startX
            @document.fillColor @document._fillColor... if @document._fillColor
            @emit 'pageBreak', options, this
            
        else
            @document.x += @lineWidth + @columnGap
            @document.y = @startY
            @emit 'columnBreak', options, this
        
        @emit 'sectionStart', options, this
            
module.exports = LineWrapper
