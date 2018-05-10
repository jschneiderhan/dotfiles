module Metrics
  module Wbt
    class Olms < DwhMetric
      def raw_data
        end_date = DB.literal(Date.yesterday)

        DB.fetch %(
          SELECT  unnest(array['olmSmoking', 'olmPhysicallyActive', 'olmHealthyDiet', 'olmAlcoholUse']) as key,
                  unnest(array[olmSmoking, olmPhysicallyActive, olmHealthyDiet, olmAlcoholUse]) AS value
          FROM (
            SELECT
              (SELECT CAST(COUNT(CASE WHEN currentsmokerstatus_measure = 'false' THEN 1 END) AS FLOAT )) /
              GREATEST((
                (SELECT CAST(COUNT(CASE WHEN currentsmokerstatus_measure = 'true' THEN 1 END) AS FLOAT )) +
                (SELECT CAST(COUNT(CASE WHEN currentsmokerstatus_measure = 'false' THEN 1 END) AS FLOAT ))
              ), 1)*100 AS olmSmoking,

              (SELECT CAST(COUNT(CASE WHEN exercisevitalsign_measure = 'sufficient' THEN 1 END) AS FLOAT )) /
              GREATEST((
                (SELECT CAST(COUNT(CASE WHEN exercisevitalsign_measure = 'sufficient' THEN 1 END) AS FLOAT )) +
                (SELECT CAST(COUNT(CASE WHEN exercisevitalsign_measure = 'insufficient' THEN 1 END) AS FLOAT ))
              ), 1)*100 AS olmPhysicallyActive,

              (SELECT CAST(COUNT(CASE WHEN fruitvegetableconsumptionrisk_measure = 'sufficient' THEN 1 END) AS FLOAT )) /
              GREATEST((
                (SELECT CAST(COUNT(CASE WHEN fruitvegetableconsumptionrisk_measure = 'sufficient' THEN 1 END) AS FLOAT )) +
                (SELECT CAST(COUNT(CASE WHEN fruitvegetableconsumptionrisk_measure = 'insufficient' THEN 1 END) AS FLOAT ))
              ), 1)*100 AS olmHealthyDiet,

              (SELECT CAST(COUNT(CASE WHEN greaterthanmoderatedrinking_measure = 'false' THEN 1 END) AS FLOAT )) /
              GREATEST((
                (SELECT CAST(COUNT(CASE WHEN greaterthanmoderatedrinking_measure = 'true' THEN 1 END) AS FLOAT )) +
                (SELECT CAST(COUNT(CASE WHEN greaterthanmoderatedrinking_measure = 'false' THEN 1 END) AS FLOAT ))
              ), 1)*100 AS olmAlcoholUse

            FROM c.recent_survey_results(#{sanitized_start_date},#{end_date})
            WHERE segment_code IN (#{sanitized_segment_codes})
          ) as temp;
        ).squish
      end

      private

      def sanitized_segment_codes
        segments.map { |s| DB.literal(s.code) }.join(",")
      end
    end
  end
end
