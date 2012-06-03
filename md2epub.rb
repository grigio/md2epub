# encoding: utf-8
#
# Copyright (c) 2012 Shunsuke Ito
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

# gem require
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'pp'
require 'uuidtools'
require 'erb'
require 'redcarpet'
require 'digest/md5'
require 'open-uri'
require 'mime/types'
require 'RedCloth'

class FetchImages
    def initialize( tmpdir , resourcedir)
        @text = []
        @basedir = resourcedir
        @resourcedir = @basedir
        @assetdir = @basedir + "/assets/"
        @imagedir = tmpdir + "/OEBPS/images/"
        @imglist = []
        FileUtils.makedirs(@imagedir)
    end
    
    def _fetchImage( url, filename )
    
        @imglist.each{|img|
            if img[:url] == url then
                puts "already :" + url
                return nil
            end
        }
    
        open(@imagedir + filename, 'wb') do |file|
            open(url) do |data|
                file.write(data.read)
                puts "fetch :" + url
            end
        end
        return true
    end    
    
    def fetch( text )
    
        pwd = Dir::pwd
        Dir::chdir(@resourcedir)

        # Regexp image URL
        reg = /img.+src=[\"|\']?([\-_\.\!\~\*\'\(\)a-zA-Z0-9\;\/\?\:@&=\$\,\%\#]+\.(jpg|jpeg|png|gif|bmp))/i
        
        text = text.encode("UTF-16", :invalid => :replace, :replace => '').encode("UTF-8")

        text.scan(reg).each do |item|
            url = item[0]
            id = Digest::MD5.new.update(item[0]).to_s
            filename = %Q(#{id}.#{item[1]})
            
            p url
            
            if _fetchImage( url, filename ) then            
                img =  {
                    :url => url,
                    :id => id,
                    :file => filename
                }
                @imglist.push(img)
            end            
            apimgfile = "../images/" + filename
            text.gsub!(url , apimgfile)
        end
                
        Dir::chdir(pwd)
        return text
    end

end


class Markdown2EPUB
    def initialize(params=nil)
        @booktitle = ""
        @bookname = "md2epub.epub"
        @uuid = ""
        @aut = ""
        @publisher =""
        @pubdate =""
        @params = params
        @basedir = Dir.pwd
        @resourcedir = @basedir
        @assetdir = @basedir + "/assets/"
        @pages = []
        @tmpdir = nil
        @debug = false
    end
    
    def set_dir( dir )
        @resourcedir = dir
    end
   
    def _copy_asset_files
        FileUtils.copy(@assetdir +"mimetype", @tmpdir)
        FileUtils.cp_r(Dir.glob( @assetdir + "META-INF"), @tmpdir)
        FileUtils.cp_r(Dir.glob( @assetdir + "OEBPS"), @tmpdir)
    end    


    def _copy_images
        origin_imagedir = @resourcedir + "/images"
        if File.exists?( origin_imagedir ) then
            epub_imagedir = @tmpdir + "/OEBPS/"
            FileUtils.makedirs( epub_imagedir )
            FileUtils.cp_r(Dir.glob( origin_imagedir ), epub_imagedir)
        end
    end

    
    def _build_page( page, pagebody, file )
        html =""
        pagetitle = page[:pagetitle]        
        erbfile = @assetdir +"page.xhtml.erb"
        
        open(erbfile, 'r') {|erb|
            html = ERB.new( erb.read , nil, '-').result(binding)
            open( file, "w") {|f|
                f.write( html )
            }
        }
    end

    
    def _build_opf
        opf = ""
        pages = @pages
        erbfile = @assetdir +"content.opf.erb"
        
        imagelist = []        
        Dir.glob( @tmpdir + "/OEBPS/images/*" ) {|img|
            imagelist.push({
                :fname =>  File.basename(img),
                :mediatype => MIME::Types.type_for(img)[0].to_s 
            })
        }
        
        open(erbfile, 'r') {|erb|
            opf = ERB.new( erb.read , nil, '-').result(binding)
            open( @tmpdir + "/OEBPS/content.opf", "w") {|f|
                f.write( opf )
            }
        }
    end


    def _build_toc
        html = ""
        pages = @pages
        erbfile = @assetdir +"toc.xhtml.erb"
        
        open(erbfile, 'r') {|erb|
            html = ERB.new( erb.read , nil, '-').result(binding)
            open( @tmpdir + "/OEBPS/toc.xhtml", "w") {|f|
                    f.write( html )
            }
        }
    end    

    
    def _build_cover
        html = ""
        pages = @pages
        erbfile = @assetdir +"cover.xhtml.erb"
        
        open(erbfile, 'r') {|erb|
            html = ERB.new( erb.read , nil, '-').result(binding)
            open( @tmpdir + "/OEBPS/text/cover.xhtml", "w") {|f|
                    f.write( html )
            }
        }
    end       

    def _build_colophone
        html = ""
        pages = @pages
        erbfile = @assetdir +"colophone.xhtml.erb"
        
        open(erbfile, 'r') {|erb|
            html = ERB.new( erb.read , nil, '-').result(binding)
            open( @tmpdir + "/OEBPS/text/colophone.xhtml", "w") {|f|
                    f.write( html )
            }
        }
    end  
    
    def _load_settings
        file = @resourcedir + "/epub.yaml"
        raise "Can't open #{file}." if file.nil? || !File.exist?(file)
        setting = YAML.load_file(file)
      
        @bookname = setting["bookname"]
        @booktitle = setting["booktitle"]
        @aut = setting["aut"]
        @lang = setting["lang"]
        @publisher = setting['publisher']
        @debug = setting['debug']
        
        if setting.key?('uuid') then
            @uuid = UUIDTools::UUID.sha1_create(UUID_DNS_NAMESPACE, setting['uuid']).to_s
        else
            @uuid = UUIDTools::UUID.random_create.to_s
        end
        
        if setting.key?('pubdate') then
            @pubdate = setting['pubdate']
        else
            @pubdate = Time.now.gmtime.iso8601
        end
    end

    
    def make_epub( tmpdir , epubfile)
        fork {
            Dir.chdir(tmpdir) {|d|
                exec("zip", "-0X", "#{epubfile}", "mimetype")
            }
        }
        Process.waitall
        fork {
            Dir.chdir(tmpdir) {|d|
                exec("zip -Xr9D #{epubfile}" + ' * -x "*.DS_Store" -x mimetype META-INF OEBPS')
            }
        }
        Process.waitall
        
        FileUtils.cp( %Q(#{tmpdir}/#{epubfile}), @resourcedir)
    end


    def pre_replace( str )
        str.gsub!("&", "&amp;")
        str.gsub!(/^([=-]+)(.+)$/){
            $&.gsub(/[=-]/,"#")
        }

        str.gsub!(/^■(.+)$/){
            $&.gsub("■","###")
        }
        
        # footnote
        footnotes = Array.new
        str.gsub!(/\[\*([\d]+)\]/){
            unless footnotes[$1.to_i] then
                footnotes[$1.to_i] = true
                '<a class="fn" epub:type="noteref" id="ref'+ $1 +'" href="#note' + $1 +'">*' + $1 +'</a>'
            else
                '[footnote=' + $1 + ']'
            end
        }
        
        return str    
    end

    def after_replace( str )
        str += ""
        
        unless str.valid_encoding? then
            str = str.encode("UTF-8", "UTF-8", :invalid => :replace, :undef => :replace, :replace => '?')
        end
        str.gsub!(/^<p>\[footnote=([\d]+)\]/){
            '<p epub:type="footnote" id="note'+ $1 +'"><a class="fn" href="#ref'+ $1 +'">*' + $1 +'</a>'
        }

        return str    
    end
   
    def build
        puts %Q(BUILD::#{@resourcedir})
                
        # load EPUB setting file
        _load_settings()
        
        # markdown Render options
        options = [
            :autolink => true,
            :fenced_code => true,
            :fenced_code_blocks => true,
            :gh_blockcode => true,
            :hard_wrap => true,
            :lax_html_blocks => true,
            :no_intra_emphasis => true,
            :no_intraemphasis => true,
            :strikethrough => true,
            :superscript => true,
            :tables => true,
            :xhtml => true
        ]
        rndr = Redcarpet::Markdown.new(Redcarpet::Render::XHTML, *options )
        
        # make working directory
        @tmpdir = Dir.mktmpdir("md2epub", @basedir)

        # Fetch Image Class
        images = FetchImages.new( @tmpdir, @resourcedir )

        # copy Asset Files
        _copy_asset_files()

        # copy Resource Images
        _copy_images()
    
        # make HTML directory
        contentdir = @tmpdir + "/OEBPS/text"
        FileUtils.mkdir( contentdir )
        
        # markdown to HTML
        get_title = Regexp.new('^[#=] (.*)$')
        get_title2 = Regexp.new('^[0-9]*\.(.*)$')

        Dir::glob( @resourcedir + "/*.{md,mkd,markdown,txt}" ).each {|file|
            # puts "#{file}: #{File::stat(file).size} bytes"
            md = File.read( file ).encode("UTF-8")            
            html =""

            # pre Replace
            md = pre_replace( md )
            
            get_title =~ md
            if $1 then
                pagetitle = $1.chomp
                md[ get_title ] = ""
            else 
                get_title2 =~ md
                if $1 then
                    pagetitle = $1.chomp
                    md[ get_title2 ] = ""
                else
                    pagetitle = File.basename(file, ".*")
                end
            end
            fname = File.basename(file, ".md") << ".xhtml"
            page = {:pagetitle => pagetitle, :file => fname }                
            
            
            # render markdown
            html = rndr.render( md )

            # after Replace
            html = after_replace( html )
            
            # Fetch Images and replace src path
            html = images.fetch( html )
            _build_page( page, html, %Q(#{contentdir}/#{fname}) )

            @pages.push page
        }            

        # textile to HTML
        get_title = Regexp.new('^h1. (.*)$')

        Dir::glob( @resourcedir + "/*.textile" ).each {|file|
            # puts "#{file}: #{File::stat(file).size} bytes"
            textile = File.read( file )
            html =""

            # pre Replace
            textile = pre_replace( textile )
            
            get_title =~ textile
            if $1 then
                pagetitle = $1.chomp
                md[ get_title ] = ""
            else 
                pagetitle = File.basename(file, ".*")
            end
            fname = File.basename(file, ".textile") << ".xhtml"
            page = {:pagetitle => pagetitle, :file => fname }                
                        
            # render textile
            html = RedCloth.new( textile ).to_html            
            
            # Fetch Images and replace src path
            html = images.fetch( html )
            _build_page( page, html, %Q(#{contentdir}/#{fname}) )

            @pages.push page
        }

        # sort by filename
        @pages.sort! {|a, b| a[:file] <=> b[:file]}

        # build EPUB meta files
        _build_opf()
        _build_toc()
        
        # build cover page
        _build_cover()
        
        # build colophone page
        _build_colophone()
        
        # ZIP!
        make_epub( @tmpdir , @bookname )
        
        # delete working directory
        unless @debug then
            FileUtils.remove_entry_secure(@tmpdir)
        end
                
    end   
end


# Run
epub = Markdown2EPUB.new
unless ARGV[0].nil? then
    if File.exists?(ARGV[0]) then
        epub.set_dir( File.realdirpath( ARGV[0] ) )
        epub.build
    else
        puts %Q(Directory not exist: #{ARGV[0]})
    end
end


