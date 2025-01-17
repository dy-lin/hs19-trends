#PREVIOUS CODE from database_parallel.R  @laijasmine

library(future)
library(fulltext)
library(pubchunks)
library(tidyverse)
library(magrittr)
library(dplyr)
library(purrr)
library(here)

# ***added lubridate***
library(lubridate)

here <- here::here

plan(multisession)

searchTerms <- read.csv(here("/raw-data/SearchTerms.csv"))
searchTerms$Term %<>% as.character()
searchTerms <- searchTerms %>% filter(Topic=="Metagenomics")


# ft_links() - get links for articles (xml and pdf).
df_raw <- NULL
for(st in searchTerms$Term[1]) {
  
  res1 <- ft_search(query = st, from = "plos", limit = 1000)
  
  mylinks %<-% ft_links(res1)$plos$ids
  
  # ft_get() - get full or partial text of articles.
  x %<-% ft_get(mylinks)
  
  x %>%
    ft_collect() %>% 
    pub_chunks(c("doi", "refDois", "history", "journal_meta", "publisher", "author", "aff", "title", "keywords", "abstract")) %>%  
    pub_tabularize() -> hold
  # .$elife
  for (nm in names(hold)){
    df_st <- map_df(hold[[nm]], `[`) %>%
      mutate(topic = st)
    df_raw <- bind_rows(df_raw,df_st)
    
  }
}

# Create simplified DF for analysis
df_raw_refined <- df_raw[, which(colSums(is.na(df_raw)) < 200)]
df_raw_refined %<>% select(-c("history.received", "journal_meta.journal.id", "journal_meta.journal.id.1", "journal_meta.journal.id.2", "journal_meta.issn", "journal_meta.publisher", ".publisher" )) %>%
  unite(col = author1, c(authors.surname, authors.given_names), sep = ", ") %>%
  mutate(Year = year(history.accepted), history.accepted = NULL) %>%
  rename("affiliation" = "aff.addr.line") %>%
  rename("journal" = "journal_meta.journal.title.group") %>%
  select(-starts_with("authors.")) %>% 
  select(-starts_with("aff.")) %>%
  distinct()
# ***changed data_raw to data_raw_refined***
write.csv(df_raw, here::here("data","Swapna-Metagenomics_1000.csv"))

##END OF PREVIOUS CODE @laijasmine

## CODE FOR DATA VISUALIZATION 

library(tm)
library(wordcloud)
library(RColorBrewer)

# Split data into before 2014 and after 2014
df_raw_refined <- df_raw_refined %>% 
  mutate(timeline = if_else(Year < 2014, "2006-2013", "2014-2019", "unknown" ))
  
 # Extract only the abstract field 
pre2014 <- df_raw_refined %>% 
  filter(timeline == "2006-2013") %>% 
  select(abstract)

# Convert dataframe to corpus
pre2014 <- Corpus(VectorSource(pre2014))

# Function to clean data
clean_dat <- function(corpusdata) {
dat<-tm_map(corpusdata,stripWhitespace)
dat<-tm_map(corpusdata,tolower)
dat<-tm_map(corpusdata,removeNumbers)
dat<-tm_map(corpusdata,removePunctuation)
dat<-tm_map(corpusdata,removeWords, stopwords("english"))
}

# Clean the data
pre2014clean <- clean_dat(pre2014)
pre2014clean <- tm_map(pre2014clean,removeWords, c("the", "can", "using", "also", "present", "used", "this", "two", "within", "one", "may", "including"))

# Convert to TDM format
tdm_pre2014 <- TermDocumentMatrix(pre2014clean)
TDM1 <- as.matrix(tdm_pre2014)

# Make a data frame of word frequencies
v <- sort(rowSums(TDM1),decreasing=TRUE)
freq_preclean <- data.frame(word = names(v),freq=v)
head(freq_preclean , 50)

# Extract only the abstract field  
post2014 <- df_raw_refined %>% 
  filter(timeline == "2014-2019") %>% 
  select(abstract)
  
  # Convert dataframe to corpus
post2014 <- Corpus(VectorSource(post2014))

# Clean the data
post2014clean <- clean_dat(post2014)
post2014clean<- tm_map(post2014clean, removeWords, c("the", "using", "used", "can", "also", "two", "this", "may", "found", "present", "showed", "one", "however", "including"))

# Convert to TDM format
tdm_post2014 <- TermDocumentMatrix(post2014clean)
TDM1 <- as.matrix(tdm_post2014)

# Make a data frame of word frequencies
v <- sort(rowSums(TDM1),decreasing=TRUE)
freq_postclean2014 <- data.frame(word = names(v),freq=v)
head(freq_postclean2014, 50)


# Noramlize word frequencies for both timelines
freq_preclean <- freq_preclean %>%
  mutate(prop = freq / sum(freq)) %>%
  mutate(propdelta = (prop - mean(prop)) / sqrt(mean(prop)))

freq_postclean2014 <- freq_postclean2014 %>%
  mutate(prop = freq / sum(freq)) %>%
  mutate(propdelta = (prop - mean(prop)) / sqrt(mean(prop)))

# Create word clouds for each of the timelines
set.seed(1234)
wordcloud(words = freq_preclean$word, freq = freq_preclean$propdelta, 
          max.words=50, random.order=FALSE, rot.per=0.35, 
          colors=brewer.pal(8, "Dark2"))

wordcloud(words = freq_postclean2014$word, freq = freq_postclean2014$propdelta, 
          max.words=50, random.order=FALSE, rot.per=0.35, 
          colors=brewer.pal(8, "Dark2"))
          
# Create barplots of 20 most frequent words for both timelines
par(mfcol=c(2,1))
barplot(freq_preclean$propdelta[1:20], las = 2, names.arg = freq_preclean$word[1:20],
        col ="lightblue", main ="Pre-2014 Metagenomic studies, PLOS",
        ylab = "Normalized word frequencies")

barplot(freq_postclean2014$propdelta[1:20], las = 2, names.arg = freq_postclean2014$word[1:20],
        col ="gray", main ="Post-2014 Metagenomic studies, PLOS",
        ylab = "Normalized word frequencies")
